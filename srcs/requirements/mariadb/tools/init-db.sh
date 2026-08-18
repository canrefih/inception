#!/bin/bash

set -e

DATADIR="/var/lib/mysql"
INIT_FILE="/run/mysqld/init.sql"

ROOT_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_root_password)"
DB_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_password)"

cat > "$INIT_FILE" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASSWORD}';

CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

FLUSH PRIVILEGES;
EOF

chown mysql:mysql "$INIT_FILE"
chmod 600 "$INIT_FILE"

echo "Starting MariaDB..."

exec gosu mysql mariadbd \
    --init-file="$INIT_FILE" \
    --console