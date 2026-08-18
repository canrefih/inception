FROM debian:12

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2 \
        php8.2-fpm \
        php8.2-mysql \
        php8.2-curl \
        php8.2-xml \
        php8.2-mbstring \
        php8.2-zip \
        php8.2-gd \
        php8.2-redis \
        mariadb-client \
        curl \
        ca-certificates \
        tar \
    && rm -rf /var/lib/apt/lists/*

# PHP-FPM must listen on all interfaces
RUN sed -i 's|^listen = .*|listen = 0.0.0.0:9000|' \
    /etc/php/8.2/fpm/pool.d/www.conf

RUN mkdir -p /run/php \
    /var/www/html

COPY tools/setup-wordpress.sh /usr/local/bin/setup-wordpress.sh

RUN chmod +x /usr/local/bin/setup-wordpress.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/setup-wordpress.sh"]
