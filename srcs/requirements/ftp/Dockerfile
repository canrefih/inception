FROM debian:12

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        vsftpd \
        && rm -rf /var/lib/apt/lists/*

RUN useradd \
        --create-home \
        --home-dir /home/ftpuser \
        --shell /bin/false \
        ftpuser && \
    echo "/bin/false" >> /etc/shells

RUN mkdir -p /var/run/vsftpd/empty && \
    chmod 755 /var/run/vsftpd/empty

COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 21 50000-50100

ENTRYPOINT ["/entrypoint.sh"]
