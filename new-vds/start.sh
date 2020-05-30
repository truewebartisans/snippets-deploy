#!/bin/bash

# Welcome and check for domain (first param)
if [ -n "$1" ]; then
  echo "👋 Welcome! It's helpful tool for start new VDS"
  echo "→ Included: NGINX with Brotli, Certbot, ufw firewall"
  echo "→ Configured: directory and SSL for $1 domain"
else
  echo "🤔 Ouch... Domain (first parameter) not supplied!"
  echo "→ Please run this script, like this:"
  echo "→   ./start.sh example.com"
  exit 0
fi

# Add repository for NGINX, Certbot
sudo apt-add-repository -y ppa:hda-me/nginx-stable && sudo apt-add-repository ppa:certbot/certbot

# Update & Upgrade dist
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade && sudo apt autoremove -y

# Install needed packages
sudo apt install brotli nginx nginx-module-brotli ufw software-properties-common python-certbot-nginx -y

# Configure firewall
sudo cat >/etc/ufw/applications.d/nginx.ini <<EOL
[Nginx HTTP]
title=Web Server
description=Enable NGINX HTTP traffic
ports=80/tcp

[Nginx HTTPS]
title=Web Server (HTTPS)
description=Enable NGINX HTTPS traffic
ports=443/tcp

[Nginx Full]
title=Web Server (HTTP,HTTPS)
description=Enable NGINX HTTP and HTTPS traffic
ports=80,443/tcp
EOL

# Enable firewall
sudo ufw enable

# Alow connections from NGINX, OpenSSH
sudo ufw allow "Nginx Full"
sudo ufw allow "OpenSSH"

# Enable NGINX
sudo systemctl unmask nginx.service

# Configure NGINX
sudo cat >/etc/nginx/nginx.conf <<EOL
worker_processes  auto;

# Add Brotli modules
load_module "modules/ngx_http_brotli_filter_module.so";
load_module "modules/ngx_http_brotli_static_module.so";

events {
    use                 epoll;
    multi_accept        on;
    worker_connections  1024;
}

http {
    charset       utf-8;
    sendfile      on;
    tcp_nopush    on;
    tcp_nodelay   on;
    server_tokens off;
    log_not_found off;

    # MIME
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    error_log  /var/log/nginx/error.log crit;
    access_log off;

    # Timeouts
    send_timeout              2;
    keepalive_timeout         30;
    keepalive_requests        100;
    client_body_timeout       10;
    reset_timedout_connection on;

    # Max body size
    client_max_body_size 4m;

    # Cache
    open_file_cache          max=200000 inactive=20s;
    open_file_cache_valid    30s;
    open_file_cache_errors   on;
    open_file_cache_min_uses 2;

    # Gzip
    gzip            on;
    gzip_vary       on;
    gzip_disable    "msie6";
    gzip_proxied    any;
    gzip_comp_level 6;

    # File types for compress via gzip
    gzip_types  text/plain text/css application/json application/x-javascript text/xml 
                application/xml application/xml+rss text/javascript application/javascript 
                image/svg+xml image/gif image/png image/jpeg image/x-icon image/webp;

    # SSL
    ssl_session_timeout       1d;
    ssl_session_tickets       off;
    ssl_session_timeout       1d;
    ssl_session_cache         shared:SSL:10m;
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # SSL root cert
    ssl_dhparam /etc/ssl/certs/dhparam.pem;

    # Add header
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Load configs
    include /usr/share/nginx/modules/*.conf;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOL

# Configure Brotli
sudo cat >/etc/nginx/conf.d/brotli.conf << EOL
# Brotli
brotli            on;
brotli_static     on;
brotli_comp_level 6;

# File types to compress via Brotli
brotli_types application/atom+xml application/javascript application/json application/rss+xml
             application/vnd.ms-fontobject application/x-font-opentype application/x-font-truetype
             application/x-font-ttf application/x-javascript application/xhtml+xml application/xml
             font/eot font/opentype font/otf font/truetype image/svg+xml image/vnd.microsoft.icon
             image/x-icon image/x-win-bitmap text/css text/javascript text/plain text/xml;
EOL

# Add website configuration for getting cert by Certbot
sudo cat >/etc/nginx/sites-available/$1.conf << EOL
server {
    listen 80;
    listen [::]:80;

    server_name $1 www.$1;
    root /var/www/$1/html;
    index index.html;
}
EOL

# Enable website
sudo ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/

# Restart NGINX
sudo nginx -t && sudo systemctl restart nginx

# Root cert generate
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# Create website directory, set ownership
sudo mkdir -p /var/www/$1/html
sudo chown -R $USER:$USER /var/www/

# Get SSL cert by Certbot
sudo certbot --nginx certonly

# Add website configuration
sudo cat >/etc/nginx/sites-available/$1.conf << EOL
server {
    listen 80;
    listen [::]:80;

    server_name $1 www.$1;
    return 301 https://$1$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name www.$1;
    return 301 https://$1$request_uri;

    ssl_certificate /etc/letsencrypt/live/$1/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$1/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$1/chain.pem;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $1;
    root /var/www/$1/html;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$1/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$1/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$1/chain.pem;
}
EOL

# Restart NGINX (again)
sudo nginx -t && sudo systemctl restart nginx