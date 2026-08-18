FROM debian:12

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        redis-server && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 6379

CMD ["redis-server", "--bind", "0.0.0.0", "--protected-mode", "no"]
