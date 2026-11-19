#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# SIA Docker Entrypoint
# ─────────────────────────────────────────────────────────────────────────────

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-sia}"
DB_USER="${DB_USER:-sia_user}"
DB_PASS="${DB_PASS:-sia_password}"
DATA_FILE="/var/www/html/Data.php"

# ── Generate Data.php ─────────────────────────────────────────────────────────
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

# ── Wait for MySQL to be ready ────────────────────────────────────────────────
echo "[SIA] Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
export MYSQL_PWD="${DB_PASS}"
MAX_TRIES=90
COUNT=0
until mysqladmin ping -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" --silent 2>/dev/null; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_TRIES ]; then
        echo "[SIA] ERROR: MySQL did not become ready after ${MAX_TRIES} attempts. Exiting."
        exit 1
    fi
    echo "[SIA] Waiting... (${COUNT}/${MAX_TRIES})"
    sleep 2
done
echo "[SIA] MySQL is ready!"

# ── Auto-install database schema on first run ─────────────────────────────────
if [ "${SIA_AUTO_INSTALL:-false}" = "true" ]; then
    echo "[SIA] Checking if database '${DB_NAME}' needs initialization..."

    TABLE_COUNT=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" \
        --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")

    # Trim whitespace
    TABLE_COUNT=$(echo "$TABLE_COUNT" | tr -d '[:space:]')

    if [ "${TABLE_COUNT:-0}" -lt "5" ]; then
        echo "[SIA] Database has ${TABLE_COUNT} tables — running schema setup..."

        for f in \
            /var/www/html/install/OpensisSchemaMysqlInc.sql \
            /var/www/html/install/OpensisProcsMysqlInc.sql \
            /var/www/html/install/OpensisTriggerMysqlInc.sql; do
            if [ -f "$f" ]; then
                FNAME=$(basename "$f")
                echo "[SIA] Importing: ${FNAME} ..."
                mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "${DB_NAME}" < "$f"
                RC=$?
                if [ $RC -ne 0 ]; then
                    echo "[SIA] WARNING: ${FNAME} finished with exit code ${RC} — continuing."
                else
                    echo "[SIA] OK: ${FNAME} imported."
                fi
            else
                echo "[SIA] SKIP: $f not found."
            fi
        done

        echo "[SIA] Schema setup complete."
    else
        echo "[SIA] DB already has ${TABLE_COUNT} tables — skipping schema."
    fi
fi

unset MYSQL_PWD

# ── Fix file permissions ──────────────────────────────────────────────────────
echo "[SIA] Setting file permissions..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/Data.php 2>/dev/null || true
chmod -R 775 /var/www/html/assets 2>/dev/null || true
echo "[SIA] Permissions OK."

# ── Start Apache ──────────────────────────────────────────────────────────────
echo "[SIA] Starting Apache..."
exec "$@"
