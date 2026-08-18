# Developer Documentation — Inception

This document describes the internal design and implementation details of the Inception infrastructure. It is intended for anyone who needs to understand, modify, or extend the project. For basic installation and usage instructions, see `USER_DOC.md`.

---

## 1. Overview

Inception is a multi-container infrastructure built with Docker Compose, composed of **seven custom-built services**:

- **NGINX** — public entry point, terminates TLS, serves WordPress and static showcase.
- **WordPress** — application layer, running PHP-FPM.
- **MariaDB** — relational database.
- **Redis** — object cache for WordPress.
- **FTP** — file transfer service for WordPress data.
- **Adminer** — web-based database administration interface.
- **cAdvisor** — container resource monitoring and metrics.

No pre-built service images are used (e.g. no `wordpress:latest` or `mariadb:latest` from Docker Hub) — every image is built from a custom `Dockerfile`, based on Debian 12.

---

## 2. Architecture

```text
                           HTTPS :443
                               |
                               v
                      +----------------+
                      |     NGINX      |
                      |  TLS / HTTPS   |
                      +-------+--------+
                              |
                 +------------+-------------+
                 |                          |
                 | FastCGI                  | Static files
                 v                          v
          +-------------+          +----------------+
          |  WordPress  |          |    Showcase    |
          |   PHP-FPM   |          |  HTML/CSS/JS   |
          +------+------+          +----------------+
                 |
          +------+------+
          |             |
          v             v
    +-----------+   +---------+
    |  MariaDB  |   |  Redis  |
    | Database  |   |  Cache  |
    +-----------+   +---------+

    Additional services:

    +---------+       +----------+
    |   FTP   |       | Adminer  |
    +---------+       +----------+
         |                 |
         |                 |
         +------ Docker ---+
                Network

                 +----------+
                 | cAdvisor |
                 | Metrics  |
                 +----------+

                   Docker network:
                     srcs_inception
```

**Port mapping:**

- **443** → NGINX (HTTPS public)
- **8080** → Adminer (web-based DB admin)
- **8081** → cAdvisor (metrics interface)
- **21** → FTP (control connection)
- **50000-50100** → FTP (passive mode)

WordPress, MariaDB, and Redis are reachable only from inside the `srcs_inception` Docker network, using their Docker Compose service names as hostnames:

```text
nginx     -> wordpress:9000   (FastCGI)
wordpress -> mariadb:3306     (MySQL protocol)
wordpress -> redis:6379       (Redis protocol)
adminer   -> mariadb:3306     (MySQL protocol)
ftp       -> wordpress_data   (bind mount)
```

No `network: host`, Docker `--link`, or legacy linking mechanisms are used — all inter-service communication relies on the Docker Compose bridge network's built-in DNS resolution.

---

## 3. Directory Structure

```text
inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/
│   ├── .gitkeep
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── ftp_password.txt
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── my.cnf
        │   └── tools/
        │       └── init-db.sh
        │
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── nginx.conf
        │   ├── tools/
        │   │   └── setup-nginx.sh
        │   └── website/
        │       ├── index.html
        │       ├── style.css
        │       └── script.js
        │
        ├── wordpress/
        │   ├── Dockerfile
        │   └── tools/
        │       └── setup-wordpress.sh
        │
        ├── redis/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        ├── ftp/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        ├── adminer/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        └── cadvisor/
            ├── Dockerfile
            └── tools/
                └── ...
```

Each service lives in its own subdirectory under `srcs/requirements/`, with its own `Dockerfile` and setup scripts, keeping build logic isolated and easy to maintain.

---

## 4. Makefile Targets

The root `Makefile` wraps Docker Compose commands:

| Target         | Effect                                                            |
|----------------|--------------------------------------------------------------------|
| `make` / `make up` | Runs `docker compose -f srcs/docker-compose.yml up -d`        |
| `make build`   | Builds all service images                                         |
| `make ps`      | Lists running containers                                           |
| `make stop`    | Stops running containers without removing them                    |
| `make start`   | Starts previously stopped containers                               |
| `make restart` | Restarts all containers                                            |
| `make logs`    | Tails logs from all services                                       |
| `make down`    | Stops and removes containers                                       |
| `make fclean`  | Removes containers, volumes, and project images                    |
| `make re`      | Full clean followed by a rebuild                                   |

---

## 5. Docker Compose Configuration

The infrastructure is defined in:

```text
srcs/docker-compose.yml
```

It declares:

- **Services** — `nginx`, `wordpress`, `mariadb`, `redis`, `ftp`, `adminer`, `cadvisor`, each built from its own Dockerfile.
- **Networks** — the single bridge network `srcs_inception`.
- **Volumes** — bind-mounted host directories for persistent data.
- **Secrets** — file-based Docker secrets for database and service passwords.
- **Dependencies** — service start order and health checks (e.g. WordPress depends on MariaDB being available).
- **Restart policies** — containers restart automatically unless explicitly stopped.
- **Port mappings** — selective port exposure for HTTPS, Adminer, cAdvisor, and FTP.

---

## 6. Service Implementation Details

### 6.1 NGINX

**Base image:** Debian 12

**Responsibilities:**
- Listens on port 443 only (port 80 is never opened).
- Terminates TLS/SSL using a self-signed certificate.
- Serves static WordPress assets directly.
- Forwards PHP requests to the WordPress container via FastCGI.
- Serves the static showcase website at `/showcase/`.

**Key configuration (`nginx.conf`):**

```nginx
listen 443 ssl;
server_name recan.42.fr;

ssl_certificate /etc/nginx/ssl/inception.crt;
ssl_certificate_key /etc/nginx/ssl/inception.key;
ssl_protocols TLSv1.2 TLSv1.3;
```

**WordPress routing:**

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}

location ~ \.php$ {
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTP_HOST $host;

    fastcgi_pass wordpress:9000;
}
```

**Showcase routing:**

```nginx
location /showcase/ {
    alias /var/www/showcase/;
    try_files $uri $uri/ /showcase/index.html;
}
```

**TLS certificate generation:**

The entrypoint script (`setup-nginx.sh`) checks for an existing certificate at container startup and generates one with OpenSSL if missing:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/inception.key \
  -out /etc/nginx/ssl/inception.crt \
  -subj "/CN=recan.42.fr"
```

Certificate and key are stored at:

```text
/etc/nginx/ssl/inception.crt
/etc/nginx/ssl/inception.key
```

TLS 1.2 and TLS 1.3 are both enabled; older protocol versions are disabled.

---

### 6.2 WordPress

**Base image:** Debian 12

**Installed packages:**
- PHP 8.2
- PHP-FPM
- PHP MySQL extension
- PHP cURL, GD, mbstring, XML, ZIP
- MariaDB client
- curl, ca-certificates, tar

**Entrypoint logic (`setup-wordpress.sh`):**

1. Create the WordPress web root directory if it doesn't exist.
2. Download and extract WordPress core files if not already present (idempotent — skipped on subsequent restarts thanks to the persistent volume).
3. Wait/poll until MariaDB is reachable on `mariadb:3306`.
4. Generate `wp-config.php` if missing, injecting DB host, name, user, password (read from the Docker secret file), and Redis caching settings.
5. Set correct file ownership/permissions for the web server user.
6. Launch PHP-FPM in the foreground (`exec php-fpm ...`) so the container stays alive and logs go to stdout/stderr.

**Database connection:**

```text
DB_HOST=mariadb
DB_NAME=wordpress
DB_USER=wpuser
DB_PASSWORD=<from /run/secrets/db_password>
```

**Redis cache configuration:**

```text
WP_REDIS_HOST=redis
WP_REDIS_PORT=6379
```

**PHP-FPM listens on:**

```text
0.0.0.0:9000
```

Port 9000 is *not* published to the host — only reachable from NGINX over the internal network.

---

### 6.3 MariaDB

**Base image:** Debian 12

**Installed packages:**
- MariaDB Server
- MariaDB Client
- gosu (used to drop privileges when running mysqld as the correct user)

**Entrypoint logic (`init-db.sh`):**

1. Read the root and WordPress DB passwords from the Docker secret files.
2. Check for the initialization marker file:

   ```text
   /var/lib/mysql/.inception_initialized
   ```

3. If the marker is **absent** (first run):
   - Start a temporary local `mysqld` instance (not bound to the network, socket-only).
   - Wait until it accepts connections.
   - Create the WordPress database.
   - Create the WordPress database user and grant it privileges on that database.
   - Shut down the temporary instance cleanly.
   - Write the marker file so this block is skipped on future container starts.
4. Start MariaDB normally in the foreground (`exec mariadbd`), bound to `0.0.0.0:3306` inside the container's network namespace.

This pattern makes the initialization **idempotent** — the container can be stopped and restarted, or the image rebuilt, without re-running (or corrupting) the database setup, as long as the persistent volume is preserved.

**Database port:**

```text
3306 (internal network only)
```

---

### 6.4 Redis

**Base image:** Debian 12

**Responsibilities:**
- Provides object caching for WordPress.
- Improves application responsiveness by reducing repeated database operations.
- Listens on port 6379 (internal network only).

**Configuration:**

Redis is configured to listen on `0.0.0.0:6379` inside the container's network namespace, making it reachable to WordPress as `redis:6379`.

Redis port 6379 is **not** published to the host — it is reachable only from within the Docker network.

**WordPress integration:**

WordPress can optionally use Redis for caching if a caching plugin is installed and configured with:

```text
WP_REDIS_HOST=redis
WP_REDIS_PORT=6379
```

---

### 6.5 FTP

**Base image:** Debian 12

**Responsibilities:**
- Provides file transfer access to the WordPress data directory.
- Allows WordPress files to be managed without direct host filesystem access.
- Uses the same persistent WordPress volume as the WordPress container.

**Configuration:**

- Mounts `wordpress_data` at `/home/ftpuser/wordpress`.
- Listens on port 21 for control connections.
- Uses passive mode on ports 50000-50100.
- FTP credentials (username/password) provided via Docker Secrets.

**Port mappings:**

```text
21         → FTP control connection
50000-50100 → FTP passive mode
```

---

### 6.6 Adminer

**Base image:** Debian 12

**Responsibilities:**
- Provides a lightweight, web-based interface for database administration.
- Allows inspection and modification of the WordPress database without exposing MariaDB directly.
- Listens on port 8080.

**Database connection:**

Adminer connects to MariaDB through the Docker network using:

```text
Server:   mariadb
Port:     3306
Username: <from .env MYSQL_USER>
Password: <from /run/secrets/db_password>
Database: <from .env MYSQL_DATABASE>
```

**Port mapping:**

```text
8080 → Adminer web interface
```

---

### 6.7 cAdvisor

**Base image:** Debian 12

**Responsibilities:**
- Collects and monitors resource usage for all running containers.
- Exposes metrics via Prometheus format.
- Provides both a web interface and metrics endpoint.

**Configuration:**

cAdvisor has read-only access to host resources:

```text
/rootfs          (read-only)
/var/run        (read-only)
/sys            (read-only)
/var/lib/docker (read-only)
```

**Port mappings:**

```text
8081 → cAdvisor web interface and metrics endpoint
```

**Metrics endpoint:**

```text
http://127.0.0.1:8081/metrics
```

**Available metrics:**

- `container_cpu_usage_seconds_total` — CPU usage per container
- `container_memory_working_set_bytes` — Memory usage per container
- `container_fs_usage_bytes` — Filesystem usage per container
- Additional Docker container metrics in Prometheus format

---

## 7. Networking

A single custom bridge network is used:

```text
srcs_inception
```

Docker Compose's built-in DNS allows each service to resolve the others by their Compose service name:

```text
nginx     -> wordpress:9000   (FastCGI)
wordpress -> mariadb:3306     (MySQL protocol)
wordpress -> redis:6379       (Redis protocol)
adminer   -> mariadb:3306     (MySQL protocol)
ftp       -> (bind mount only)
cadvisor  -> (read-only mounts)
```

Only the `nginx` service publishes ports to the host (`443:443`, plus `8080:8080` for Adminer, `8081:8081` for cAdvisor, `21:21` and `50000-50100:50000-50100` for FTP). `wordpress`, `mariadb`, and `redis` have no `ports:` mapping — they are reachable only from within the Docker network.

---

## 8. Persistent Volumes

Two bind-mounted volumes back the persistent data:

| Volume     | Host path                    | Container path      |
|------------|-------------------------------|----------------------|
| WordPress  | `/home/recan/data/wordpress`   | `/var/www/html`      |
| MariaDB    | `/home/recan/data/db`          | `/var/lib/mysql`     |

Using bind mounts (rather than anonymous Docker-managed volumes) ensures the data is stored at a predictable, inspectable location on the host and survives `docker compose down` as long as the host directories aren't deleted.

The static showcase website is part of the NGINX application configuration (copied into the image) and does not depend on a persistent volume.

---

## 9. Secrets Management

Passwords are never hardcoded in `docker-compose.yml` or baked into images. Instead, Docker Secrets (file-based, for Compose in non-Swarm mode) are used:

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/ftp_password.txt
```

At runtime these are mounted inside the relevant containers at:

```text
/run/secrets/db_password
/run/secrets/db_root_password
/run/secrets/wp_admin_password
/run/secrets/ftp_password
```

Setup scripts read the secret files directly (e.g. `cat /run/secrets/db_password`) rather than relying on plaintext environment variables for sensitive values.

---

## 10. Build Process

Each service Dockerfile follows roughly the same pattern:

1. Start `FROM debian:12`.
2. Install required packages with `apt-get update && apt-get install -y ...`, cleaning up apt cache afterward to keep image size down.
3. Copy configuration files and entrypoint scripts into the image.
4. Set the entrypoint script as executable and define it as the container's `ENTRYPOINT` or `CMD`.
5. Expose the relevant port (`443` for NGINX, `9000` for WordPress, `3306` for MariaDB, `6379` for Redis, `21` for FTP, `80` for Adminer, `8080` for cAdvisor) — note `EXPOSE` alone does not publish the port to the host; only the `ports:` section in `docker-compose.yml` does that.

Images are built locally by Docker Compose (`make build` / `make`), tagged as:

```text
mariadb:inception
wordpress:inception
nginx:inception
redis:inception
ftp:inception
adminer:inception
cadvisor:inception
```

---

## 11. Debugging and Development Workflow

### Rebuilding a single service

After modifying a service's Dockerfile or configuration:

```bash
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d nginx
```

### Inspecting logs

```bash
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml logs -f mariadb
docker compose -f srcs/docker-compose.yml logs -f redis
docker compose -f srcs/docker-compose.yml logs -f ftp
docker compose -f srcs/docker-compose.yml logs -f adminer
docker compose -f srcs/docker-compose.yml logs -f cadvisor
```

### Shelling into a container

```bash
docker exec -it nginx sh
docker exec -it wordpress sh
docker exec -it mariadb sh
docker exec -it redis redis-cli
docker exec -it ftp sh
docker exec -it adminer sh
docker exec -it cadvisor sh
```

### Verifying the database directly

```bash
docker exec -it mariadb sh
mariadb -u"$MYSQL_USER" -p"$(cat /run/secrets/db_password)" "$MYSQL_DATABASE"
```

```sql
SHOW TABLES;
```

Expected tables include `wp_posts`, `wp_users`, `wp_options`, `wp_comments`, `wp_postmeta`, among others created by WordPress core.

### Verifying Redis connectivity

```bash
docker exec -it redis redis-cli ping
```

Should return `PONG`.

### Verifying cAdvisor metrics

```bash
curl -s http://127.0.0.1:8081/metrics | head -20
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total'
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes' | head -5
```

### Verifying FTP connectivity

```bash
# Using lftp
lftp -u ftpuser,<password> 127.0.0.1
lftp ftpuser@127.0.0.1:~> ls
```

### Verifying TLS support

```bash
curl -k -I --tlsv1.2 https://recan.42.fr/
curl -k -I --tlsv1.3 https://recan.42.fr/
```

### Verifying port 80 is closed

```bash
curl -I http://recan.42.fr/
```

This should fail to connect, confirming HTTP is not exposed.

### Verifying showcase website

```bash
curl -k -I https://recan.42.fr/showcase/
```

Should return HTTP 200 without involving PHP-FPM.

### Inspecting volumes and network

```bash
docker volume ls
docker volume inspect srcs_wordpress_data
docker volume inspect srcs_db_data
docker network ls
docker network inspect srcs_inception
```

---

## 12. Design Rationale

**Why Docker (and not VMs)?**
Docker provides process-level isolation while sharing the host kernel, making containers significantly lighter and faster to start than full virtual machines, while still isolating each service's filesystem, dependencies, and process space.

**Why Docker Compose?**
Compose declaratively defines all services, networks, volumes, secrets, and their relationships in a single file, so the entire infrastructure can be reproduced with one command (`make`) instead of manually creating and wiring containers together.

**Why custom Dockerfiles instead of official images?**
The project requirement is to build each service from a base Debian image rather than relying on pre-built application images, which forces a deeper understanding of what each service actually needs to run (packages, configuration, initialization) rather than treating it as a black box.

**Why file-based Docker Secrets instead of environment variables for passwords?**
Environment variables are visible via `docker inspect` and process listings, whereas secrets mounted as files under `/run/secrets/` are only readable by processes inside the container with access to that path, reducing the risk of accidental credential exposure.

**Why bind-mounted host directories instead of named Docker volumes?**
Bind mounts to a known, fixed host path (`/home/recan/data/...`) make the data location explicit and easy to inspect, back up, or migrate, and satisfy the project's persistence requirements across container recreation and host reboots.

**Why seven services instead of just three?**
The expanded infrastructure demonstrates:
- **Redis** — caching strategies and performance optimization
- **FTP** — file transfer protocols and access control
- **Adminer** — web-based database administration
- **cAdvisor** — monitoring, metrics collection, and observability

These additional services showcase a more realistic, production-like infrastructure while maintaining simplicity and clarity.

---

## 13. Known Constraints

- The TLS certificate is self-signed and intended only for the local/development environment defined by the project subject — it is not suitable for production use as-is.
- Only HTTPS (port 443) is exposed to the host; HTTP (port 80) is intentionally never published.
- Database and PHP-FPM ports are only reachable within the `srcs_inception` Docker network, never from the host directly.
- Redis, FTP, Adminer, and cAdvisor are intended for local/development use and should not be exposed to untrusted networks without additional security measures.
- The static showcase website is read-only and served via NGINX without dynamic content generation.

---

## 14. Performance and Optimization

**Redis caching:**
Redis can significantly improve WordPress performance by caching database query results. Install and configure a WordPress caching plugin (e.g., Redis Object Cache or WP Redis) to take advantage of this.

**NGINX configuration:**
NGINX is configured to serve static assets efficiently, reducing load on PHP-FPM. Gzip compression and caching headers can be further tuned for production use.

**Database indexing:**
MariaDB should have appropriate indexes on frequently queried columns. WordPress tables come with indexes, but custom tables should be indexed similarly.

**Monitoring:**
Use cAdvisor to identify resource bottlenecks. High memory usage may indicate missing caching, high CPU usage may indicate slow queries or plugins.

---

## 15. AI Usage Disclosure

AI assistance was used during development for:

- Structuring and formatting the project documentation (`README.md`, `USER_DOC.md`, `DEV_DOC.md`).
- Improving documentation clarity and readability.
- Reviewing the Docker Compose configuration against the project requirements.
- Helping identify configuration and evaluation issues during development.
- Assisting with troubleshooting Docker, NGINX, PHP-FPM, MariaDB, Redis, FTP, Adminer, and cAdvisor commands.
- Reviewing the expanded seven-service architecture and integration points.

AI was not used as a replacement for understanding the infrastructure or its implementation. The Dockerfiles, configuration files, and scripts were developed, tested, and validated as part of the actual project implementation.
