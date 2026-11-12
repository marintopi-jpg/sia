#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# SIA Docker Entrypoint
# Generates Data.php from environment variables if it does not already exist,
# then waits for MySQL to be ready before starting Apache.
# ─────────────────────────────────────────────────────────────────────────────

DATA_FILE="/var/www/html/Data.php"

# Required environment variables with defaults
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-sia}"
DB_USER="${DB_USER:-sia_user}"
DB_PASS="${DB_PASS:-sia_password}"

# Generate Data.php if it doesn't exist or if FORCE_DATA_REGEN=true
if [ ! -f "$DATA_FILE" ] || [ "${FORCE_DATA_REGEN:-false}" = "true" ]; then
    echo "[SIA] Generating Data.php with database config..."
    cat > "$DATA_FILE" <<EOF
<?php
\$DatabaseType     = 'mysqli';
\$DatabaseServer   = '${DB_HOST}';
\$DatabaseUsername = '${DB_USER}';
\$DatabasePassword = '${DB_PASS}';
\$DatabaseName     = '${DB_NAME}';
\$DatabasePort     = '${DB_PORT}';
?>
EOF
    chown www-data:www-data "$DATA_FILE"
    chmod 640 "$DATA_FILE"
    echo "[SIA] Data.php created successfully."
else
    echo "[SIA] Data.php already exists — skipping generation."
fi

# ─── Wait for MySQL to be ready ───────────────────────────────────────────────
echo "[SIA] Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
MAX_TRIES=60
COUNT=0
until php -r "
    \$conn = @new mysqli('${DB_HOST}', '${DB_USER}', '${DB_PASS}', '', ${DB_PORT});
    exit(\$conn->connect_error ? 1 : 0);
" 2>/dev/null; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_TRIES ]; then
        echo "[SIA] ERROR: MySQL did not become ready after ${MAX_TRIES} seconds. Exiting."
        exit 1
    fi
    echo "[SIA] MySQL not ready yet (attempt ${COUNT}/${MAX_TRIES}). Retrying in 2s..."
    sleep 2
done
echo "[SIA] MySQL is ready!"

# ─── Auto-install database schema on first run ───────────────────────────────
# If SIA_AUTO_INSTALL=true and the 'app' table doesn't exist, run the schema SQL
if [ "${SIA_AUTO_INSTALL:-false}" = "true" ]; then
    echo "[SIA] Checking if database '${DB_NAME}' needs initialization..."
    TABLE_EXISTS=$(php -r "
        \$conn = new mysqli('${DB_HOST}', '${DB_USER}', '${DB_PASS}', '${DB_NAME}', ${DB_PORT});
        \$res  = \$conn->query(\"SHOW TABLES LIKE 'app'\");
        echo \$res->num_rows;
    " 2>/dev/null || echo "0")

    if [ "$TABLE_EXISTS" = "0" ]; then
        echo "[SIA] Database is empty. Running schema setup..."
        php -r "
            \$conn = new mysqli('${DB_HOST}', '${DB_USER}', '${DB_PASS}', '${DB_NAME}', ${DB_PORT});
            \$conn->set_charset('utf8');
            \$files = [
                '/var/www/html/install/OpensisSchemaMysqlInc.sql',
                '/var/www/html/install/OpensisProcsMysqlInc.sql',
                '/var/www/html/install/OpensisTriggerMysqlInc.sql',
                '/var/www/html/install/SqlForClientSchoolInc.php',
            ];
            foreach (\$files as \$f) {
                if (!file_exists(\$f) || pathinfo(\$f, PATHINFO_EXTENSION) !== 'sql') continue;
                echo \"Running: \$f\n\";
                \$sql = file_get_contents(\$f);
                \$conn->multi_query(\$sql);
                while (\$conn->next_result()) { if (\$res = \$conn->store_result()) \$res->free(); }
                echo \"Done: \$f\n\";
            }
            echo \"Schema setup complete.\n\";
        "
        echo "[SIA] Database initialized."
    else
        echo "[SIA] Database already initialized — skipping schema setup."
    fi
fi

# ─── Start Apache ─────────────────────────────────────────────────────────────
echo "[SIA] Starting Apache..."
exec "$@"
