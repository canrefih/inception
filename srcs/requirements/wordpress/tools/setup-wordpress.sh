#!/bin/bash

set -e

WP_DIR="/var/www/html"
WP_URL="https://wordpress.org/latest.tar.gz"

DB_HOST="mariadb"
DB_NAME="${MYSQL_DATABASE}"
DB_USER="${MYSQL_USER}"
DB_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_password)"

DOMAIN="${DOMAIN_NAME}"

WP_ADMIN_USER="${WP_ADMIN_USER}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL}"
WP_ADMIN_PASSWORD="$(tr -d '\r\n' < /run/secrets/wp_admin_password)"

echo "Starting WordPress setup..."

mkdir -p "$WP_DIR"

# --------------------------------------------------
# Download WordPress
# --------------------------------------------------

if [ ! -f "$WP_DIR/wp-load.php" ]; then
    echo "Downloading WordPress..."

    curl -fsSL "$WP_URL" -o /tmp/wordpress.tar.gz

    tar -xzf /tmp/wordpress.tar.gz \
        --strip-components=1 \
        -C "$WP_DIR"

    rm -f /tmp/wordpress.tar.gz
fi

# --------------------------------------------------
# Wait for MariaDB
# --------------------------------------------------

echo "Waiting for MariaDB..."

until mariadb \
    -h "$DB_HOST" \
    -u "$DB_USER" \
    -p"$DB_PASSWORD" \
    "$DB_NAME" \
    -e "SELECT 1;" >/dev/null 2>&1
do
    sleep 2
done

echo "MariaDB connection successful."

# --------------------------------------------------
# Create wp-config.php
# --------------------------------------------------

if [ ! -f "$WP_DIR/wp-config.php" ]; then
    echo "Creating wp-config.php..."

    cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

    sed -i "s/database_name_here/${DB_NAME}/" "$WP_DIR/wp-config.php"
    sed -i "s/username_here/${DB_USER}/" "$WP_DIR/wp-config.php"
    sed -i "s/password_here/${DB_PASSWORD}/" "$WP_DIR/wp-config.php"
    sed -i "s/localhost/${DB_HOST}/" "$WP_DIR/wp-config.php"

    sed -i "/That's all, stop editing/i \
define('WP_REDIS_HOST', 'redis');\n\
define('WP_REDIS_PORT', 6379);\n\
define('WP_CACHE', true);\n\
define('WP_REDIS_CLIENT', 'phpredis');" \
        "$WP_DIR/wp-config.php"

    echo "wp-config.php created."
fi

# --------------------------------------------------
# Install WP-CLI
# --------------------------------------------------

if [ ! -f "/usr/local/bin/wp" ]; then
    echo "Downloading WP-CLI..."

    curl -fsSL \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /tmp/wp-cli.phar

    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp
fi

# --------------------------------------------------
# Install WordPress
# --------------------------------------------------

if ! wp --allow-root core is-installed --path="$WP_DIR" >/dev/null 2>&1; then

    echo "Installing WordPress..."

    wp --allow-root core install \
        --url="https://${DOMAIN}" \
        --title="Inception" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --path="$WP_DIR" \
        --skip-email

else
    echo "WordPress is already installed."
fi

# --------------------------------------------------
# Install Redis plugin
# --------------------------------------------------

if ! wp --allow-root plugin is-installed redis-cache --path="$WP_DIR" >/dev/null 2>&1; then
    echo "Installing Redis Cache plugin..."

    wp --allow-root plugin install redis-cache \
        --activate \
        --path="$WP_DIR"
else
    echo "Redis Cache plugin already installed."
fi

if ! wp --allow-root plugin is-active redis-cache --path="$WP_DIR" >/dev/null 2>&1; then
    wp --allow-root plugin activate redis-cache \
        --path="$WP_DIR"
fi

wp --allow-root redis enable --path="$WP_DIR" || true

# --------------------------------------------------
# Permissions
# --------------------------------------------------

chown -R www-data:www-data "$WP_DIR"

echo "WordPress setup complete."

# --------------------------------------------------
# Start PHP-FPM in foreground
# --------------------------------------------------

echo "Starting PHP-FPM..."

exec php-fpm8.2 -F
