#!/bin/bash

set -e

SSL_DIR="/etc/nginx/ssl"

mkdir -p "$SSL_DIR"

if [ ! -f "$SSL_DIR/inception.crt" ] || [ ! -f "$SSL_DIR/inception.key" ]; then
    echo "Generating self-signed TLS certificate..."

    openssl req -x509 \
        -nodes \
        -newkey rsa:2048 \
        -days 365 \
        -keyout "$SSL_DIR/inception.key" \
        -out "$SSL_DIR/inception.crt" \
        -subj "/C=CH/ST=Vaud/L=Lausanne/O=42/OU=Inception/CN=recan.42.fr"
fi

echo "Starting Nginx..."

exec nginx -g "daemon off;"
