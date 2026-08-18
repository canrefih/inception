FROM debian:12

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-cli \
        php8.2-mysql \
        wget \
        ca-certificates \
        && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html && \
    wget -O /var/www/html/index.php \
        https://www.adminer.org/latest.php

WORKDIR /var/www/html

EXPOSE 8080

CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/html"]
