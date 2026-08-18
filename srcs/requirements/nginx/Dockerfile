FROM debian:12

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl && \
    rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/nginx/sites-enabled/default

COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY tools/setup-nginx.sh /usr/local/bin/setup-nginx.sh

RUN chmod +x /usr/local/bin/setup-nginx.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/setup-nginx.sh"]
