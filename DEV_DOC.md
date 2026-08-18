# Developer Documentation — Inception

This document describes the internal design and implementation details of the Inception infrastructure. It is intended for anyone who needs to understand, modify, or extend the project. For basic installation and usage instructions, see `USER_DOC.md`.

---

## 1. Overview

Inception is a multi-container infrastructure built with Docker Compose, composed of three custom-built services:

- **NGINX** — public entry point, terminates TLS.
- **WordPress** — application layer, running PHP-FPM.
- **MariaDB** — database layer.

No pre-built service images are used (e.g. no `wordpress:latest` or `mariadb:latest` from Docker Hub) — every image is built from a custom `Dockerfile`, based on Debian 12.

---

## 2. Architecture

```text
                         HTTPS :443
                             |
                             v
                    +-----------------+
                    |      NGINX      |
                    |   TLS / HTTPS   |
                    +--------+--------+
                             |
                         FastCGI
                             |
                             v
                    +-----------------+
                    |    WordPress    |
                    |    PHP-FPM      |
                    +--------+--------+
                             |
                         MariaDB
                             |
                             v
                    +-----------------+
                    |     MariaDB     |
                    |    Database     |
                    +-----------------+

                    Docker network:
                      srcs_inception
```

Only NGINX exposes a port to the host (`443`). WordPress and MariaDB are reachable only from inside the `srcs_inception` Docker network, using their Docker Compose service names as hostnames:

```text
nginx     -> wordpress:9000   (FastCGI)
wordpress -> mariadb:3306     (MySQL protocol)
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
│   └── db_root_password.txt
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
        │   └── tools/
        │       └── setup-nginx.sh
        │
        └── wordpress/
            ├── Dockerfile
            └── tools/
                └── setup-wordpress.sh
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

- **Services** — `nginx`, `wordpress`, `mariadb`, each built from its own Dockerfile.
- **Networks** — the single bridge network `srcs_inception`.
- **Volumes** — bind-mounted host directories for persistent data.
- **Secrets** — file-based Docker secrets for database passwords.
- **Dependencies** — service start order (e.g. WordPress depends on MariaDB being available).
- **Restart policies** — containers restart automatically unless explicitly stopped.

---

## 6. Service Implementation Details

### 6.1 NGINX

**Base image:** Debian 12

**Responsibilities:**
- Listens on port 443 only (port 80 is never opened).
- Terminates TLS/SSL using a self-signed certificate.
- Serves static WordPress assets directly.
- Forwards PHP requests to the WordPress container via FastCGI.

**Key configuration (`nginx.conf`):**

```nginx
listen 443 ssl;
server_name recan.42.fr;
```

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

**TLS certificate generation:**

The entrypoint script (`setup-nginx.sh`) checks for an existing certificate at container startup and generates one with OpenSSL if missing:

```text
CN=recan.42.fr
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
4. Generate `wp-config.php` if missing, injecting DB host, name, user, and password (read from the Docker secret file).
5. Set correct file ownership/permissions for the web server user.
6. Launch PHP-FPM in the foreground (`exec php-fpm ...`) so the container stays alive and logs go to stdout/stderr.

**Database connection:**

```text
DB_HOST=mariadb
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
4. Start MariaDB normally in the foreground (`exec mysqld_safe` / `exec mariadbd`), bound to `0.0.0.0:3306` inside the container's network namespace.

This pattern makes the initialization **idempotent** — the container can be stopped and restarted, or the image rebuilt, without re-running (or corrupting) the database setup, as long as the persistent volume is preserved.

---

## 7. Networking

A single custom bridge network is used:

```text
srcs_inception
```

Docker Compose's built-in DNS allows each service to resolve the others by their Compose service name:

```text
wordpress -> mariadb:3306
nginx     -> wordpress:9000
```

Only the `nginx` service publishes a port to the host (`443:443`). `wordpress` and `mariadb` have no `ports:` mapping — they are reachable only from within the Docker network.

---

## 8. Persistent Volumes

Two bind-mounted volumes back the persistent data:

| Volume     | Host path                    | Container path      |
|------------|-------------------------------|----------------------|
| WordPress  | `/home/recan/data/wordpress`   | `/var/www/html`      |
| MariaDB    | `/home/recan/data/db`          | `/var/lib/mysql`     |

Using bind mounts (rather than anonymous Docker-managed volumes) ensures the data is stored at a predictable, inspectable location on the host and survives `docker compose down` as long as the host directories aren't deleted.

---

## 9. Secrets Management

Passwords are never hardcoded in `docker-compose.yml` or baked into images. Instead, Docker Secrets (file-based, for Compose in non-Swarm mode) are used:

```text
secrets/db_password.txt
secrets/db_root_password.txt
```

At runtime these are mounted inside the relevant containers at:

```text
/run/secrets/db_password
/run/secrets/db_root_password
```

Setup scripts read the secret files directly (e.g. `cat /run/secrets/db_password`) rather than relying on plaintext environment variables for sensitive values.

---

## 10. Build Process

Each service Dockerfile follows roughly the same pattern:

1. Start `FROM debian:12`.
2. Install required packages with `apt-get update && apt-get install -y ...`, cleaning up apt cache afterward to keep image size down.
3. Copy configuration files and entrypoint scripts into the image.
4. Set the entrypoint script as executable and define it as the container's `ENTRYPOINT` or `CMD`.
5. Expose the relevant port (`443` for NGINX, `9000` for WordPress, `3306` for MariaDB) — note `EXPOSE` alone does not publish the port to the host; only the `ports:` section in `docker-compose.yml` (used only for NGINX) does that.

Images are built locally by Docker Compose (`make build` / `make`), tagged as:

```text
mariadb:inception
wordpress:inception
nginx:inception
```

---

## 11. Debugging and Development Workflow

### Rebuilding a single service

After modifying a service's Dockerfile or configuration:

```bash
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d
```

### Inspecting logs

```bash
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml logs -f mariadb
```

### Shelling into a container

```bash
docker exec -it nginx sh
docker exec -it wordpress sh
docker exec -it mariadb sh
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

### Inspecting volumes and network

```bash
docker volume ls
docker volume inspect srcs_wordpress_data
docker volume inspect srcs_db_data
docker network ls
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

---

## 13. Known Constraints

- The TLS certificate is self-signed and intended only for the local/development environment defined by the project subject — it is not suitable for production use as-is.
- Only HTTPS (port 443) is exposed to the host; HTTP (port 80) is intentionally never published.
- Database and PHP-FPM ports are only reachable within the `srcs_inception` Docker network, never from the host directly.

---

## 14. AI Usage Disclosure

AI assistance was used during development for:

- Structuring and formatting the project documentation (`README.md`, `USER_DOC.md`, `DEV_DOC.md`).
- Improving documentation clarity and readability.
- Reviewing the Docker Compose configuration against the project requirements.
- Helping identify configuration and evaluation issues during development.
- Assisting with troubleshooting Docker, NGINX, PHP-FPM, and MariaDB commands.

AI was not used as a replacement for understanding the infrastructure or its implementation. The Dockerfiles, configuration files, and scripts were developed, tested, and validated as part of the actual project implementation.
