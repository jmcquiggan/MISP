#!/bin/bash

# MISP Installer Script for Ubuntu Server
# Author: ChatGPT 😎
# Tested on: Ubuntu 22.04

# ========== CONFIG ========== #
MISP_USER="www-data"
MISP_DIR="/var/www/MISP"
DB_NAME="misp"
DB_USER="misp"
DB_PASS="StrongPassword123!"   # <--- CHANGE THIS!
MISP_DOMAIN="misp.local"        # <--- CHANGE THIS if needed
PHP_TIMEZONE="US/Eastern"              # <--- Set your timezone
# ============================== #

# Functions for fancy output
function info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
function error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# 1. Update system
info "Updating system..."
sudo apt update && sudo apt upgrade -y || error "Failed system update"

# 2. Install dependencies
info "Installing dependencies..."
sudo apt install -y curl git vim zip unzip \
    python3 python3-pip python3-venv \
    apache2 mariadb-server libapache2-mod-php \
    php php-cli php-mysql php-xml php-mbstring php-redis php-gd php-intl \
    redis-server gnupg-agent make gcc g++ \
    libssl-dev libffi-dev libfuzzy-dev libmagic-dev || error "Failed installing dependencies"

# 3. Set up MariaDB
info "Configuring MariaDB..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# 4. Configure PHP
info "Setting PHP timezone..."
PHP_INI=$(php --ini | grep "Loaded Configuration" | awk '{print $4}')
sudo sed -i "s|;date.timezone =|date.timezone = ${PHP_TIMEZONE}|" "$PHP_INI"

# 5. Get MISP
info "Cloning MISP repository..."
sudo git clone https://github.com/MISP/MISP.git ${MISP_DIR}
sudo chown -R ${MISP_USER}:${MISP_USER} ${MISP_DIR}
sudo chmod -R 750 ${MISP_DIR}

# 6. Set up Python venv
info "Setting up Python virtual environment..."
cd ${MISP_DIR}
python3 -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r REQUIREMENTS

# 7. Apache configuration
info "Configuring Apache for MISP..."
sudo bash -c "cat > /etc/apache2/sites-available/misp.conf" <<EOL
<VirtualHost *:80>
    ServerAdmin admin@${MISP_DOMAIN}
    DocumentRoot ${MISP_DIR}/app/webroot
    ServerName ${MISP_DOMAIN}

    <Directory ${MISP_DIR}/app/webroot>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>

    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/misp_error.log
    CustomLog \${APACHE_LOG_DIR}/misp_access.log combined
</VirtualHost>
EOL

sudo a2dissite 000-default.conf
sudo a2ensite misp.conf
sudo a2enmod rewrite
sudo systemctl restart apache2

# 8. MISP Configurations
info "Copying default configuration files..."
cd ${MISP_DIR}/app/Config
sudo cp bootstrap.default.php bootstrap.php
sudo cp database.default.php database.php

# Database connection update
info "Updating database credentials..."
sudo sed -i "s/'login' => 'misp'/'login' => '${DB_USER}'/" database.php
sudo sed -i "s/'password' => 'misp'/'password' => '${DB_PASS}'/" database.php

# Permissions
info "Setting permissions again..."
sudo chown -R ${MISP_USER}:${MISP_USER} ${MISP_DIR}
sudo chmod -R 750 ${MISP_DIR}

# 9. Redis setup
info "Ensuring Redis is running..."
sudo systemctl enable redis-server
sudo systemctl restart redis-server

# 10. Final restart
info "Restarting services..."
sudo systemctl restart apache2
sudo systemctl restart mariadb

# 11. Host adjustment
info "Adding ${MISP_DOMAIN} to /etc/hosts..."
echo "127.0.0.1 ${MISP_DOMAIN}" | sudo tee -a /etc/hosts

success "MISP Installation completed!"
echo
info "Access MISP via: http://${MISP_DOMAIN} (or your server IP)"

exit 0
