#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# SIA Docker Entrypoint
# ─────────────────────────────────────────────────────────────────────────────

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-sia}"
DB_USER="${DB_USER:-sia_user}"
DB_PASS="${DB_PASS:-sia_password}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-root_secret}"
DATA_FILE="/var/www/html/Data.php"

# ── Write MySQL client config to skip SSL (MariaDB client in Debian) ──────────
cat > /root/.my.cnf << MYCNF
[client]
skip-ssl
[mysqladmin]
skip-ssl
MYCNF
chmod 600 /root/.my.cnf

# Shortcuts
MYSQL_APP="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASS}"
MYSQL_ROOT="mysql -h ${DB_HOST} -P ${DB_PORT} -u root -p${DB_ROOT_PASS}"

# ── Generate Data.php ─────────────────────────────────────────────────────────
if [ ! -f "$DATA_FILE" ] || [ "${FORCE_DATA_REGEN:-false}" = "true" ]; then
    echo "[SIA] Generating Data.php..."
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
    echo "[SIA] Data.php created."
else
    echo "[SIA] Data.php exists — skipping."
fi

# ── Wait for MySQL (using PHP mysqli — avoids MariaDB client SSL issues) ──────
echo "[SIA] Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
MAX_TRIES=90
COUNT=0
until php -r "
    \$c = @new mysqli('${DB_HOST}', '${DB_USER}', '${DB_PASS}', '', (int)'${DB_PORT}');
    exit(\$c->connect_error ? 1 : 0);
" 2>/dev/null; do
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_TRIES ]; then
        echo "[SIA] ERROR: MySQL did not become ready. Exiting."
        exit 1
    fi
    echo "[SIA] Waiting... (${COUNT}/${MAX_TRIES})"
    sleep 2
done
echo "[SIA] MySQL is ready!"

# ── Auto-install DB schema ────────────────────────────────────────────────────
if [ "${SIA_AUTO_INSTALL:-false}" = "true" ]; then
    echo "[SIA] Checking DB initialization..."

    TC=$(${MYSQL_APP} --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
    TC=$(echo "$TC" | tr -d '[:space:]')

    if [ "${TC:-0}" -lt "50" ]; then
        echo "[SIA] Only ${TC} tables — importing schema as root..."

        # Drop existing objects
        ${MYSQL_ROOT} "${DB_NAME}" -e "
            SET FOREIGN_KEY_CHECKS=0;
            SET @v=NULL;
            SELECT GROUP_CONCAT('DROP VIEW IF EXISTS \`',table_name,'\`')
                INTO @v FROM information_schema.views WHERE table_schema='${DB_NAME}';
            SET @v=IFNULL(@v,'SELECT 1');
            PREPARE s FROM @v; EXECUTE s; DEALLOCATE PREPARE s;
            SET @t=NULL;
            SELECT GROUP_CONCAT('DROP TABLE IF EXISTS \`',table_name,'\`')
                INTO @t FROM information_schema.tables
                WHERE table_schema='${DB_NAME}' AND table_type='BASE TABLE';
            SET @t=IFNULL(@t,'SELECT 1');
            PREPARE s FROM @t; EXECUTE s; DEALLOCATE PREPARE s;
            SET FOREIGN_KEY_CHECKS=1;
        " 2>/dev/null && echo "[SIA] DB cleaned."

        # Import SQL files
        for f in \
            /var/www/html/install/OpensisSchemaMysqlInc.sql \
            /var/www/html/install/OpensisProcsMysqlInc.sql \
            /var/www/html/install/OpensisTriggerMysqlInc.sql; do
            if [ -f "$f" ]; then
                FNAME=$(basename "$f")
                echo "[SIA] Importing ${FNAME}..."
                ${MYSQL_ROOT} "${DB_NAME}" < "$f"
                RC=$?
                [ $RC -eq 0 ] && echo "[SIA] OK: ${FNAME}" || echo "[SIA] WARN: ${FNAME} (exit ${RC}) — continuing"
            fi
        done

        # Seed essential data + admin
        echo "[SIA] Seeding admin account (os4ed / os4ed)..."
        ${MYSQL_ROOT} "${DB_NAME}" -e "
            SET sql_mode='NO_ENGINE_SUBSTITUTION';
            INSERT IGNORE INTO \`app\` (\`name\`,\`value\`) VALUES
                ('title','SIA'),('version','9.3'),('syear','2024');
            INSERT IGNORE INTO \`schools\`
                (\`id\`,\`syear\`,\`title\`,\`short_name\`,\`last_updated\`)
                VALUES (1,2024,'Shkolla','SIA',NOW());
            INSERT IGNORE INTO \`school_years\`
                (\`syear\`,\`title\`,\`start_date\`,\`end_date\`)
                VALUES (2024,'2023-2024','2023-09-01','2024-06-30');
            INSERT IGNORE INTO \`user_profiles\`
                (\`id\`,\`profile\`,\`title\`,\`last_updated\`) VALUES
                (0,'admin','Super Administrator',NOW()),
                (1,'admin','Administrator',NOW()),
                (2,'teacher','Teacher',NOW()),
                (3,'student','Student',NOW()),
                (4,'parent','Parent',NOW());
            INSERT IGNORE INTO \`staff\`
                (\`staff_id\`,\`syear\`,\`school_id\`,\`first_name\`,\`last_name\`,
                 \`username\`,\`user_name\`,\`profile_id\`,\`last_updated\`)
                VALUES (1,2024,1,'Super','Administrator','os4ed','os4ed',0,NOW());
            INSERT IGNORE INTO \`login_authentication\`
                (\`id\`,\`user_id\`,\`profile_id\`,\`username\`,\`password\`,
                 \`last_login\`,\`failed_login\`,\`last_updated\`)
                VALUES (1,1,0,'os4ed',
                '\$2y\$10\$yR8cf7lao0ed9HAyzsD1wuxerYtxXAuhPGrp5nHXI8lFoWh.ZaxJC',
                NOW(),0,NOW());
            SELECT CONCAT('Tables: ', COUNT(*)) as result
                FROM information_schema.tables WHERE table_schema='${DB_NAME}';
            SELECT CONCAT('Admin: ', username) as result FROM \`login_authentication\` LIMIT 1;
        " && echo "[SIA] Setup complete!"

    else
        echo "[SIA] DB already has ${TC} tables — skipping."
    fi
fi

# ── Fix file permissions ──────────────────────────────────────────────────────
echo "[SIA] Setting permissions..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/Data.php 2>/dev/null || true
chmod -R 775 /var/www/html/assets 2>/dev/null || true
echo "[SIA] Permissions OK."

# ── Start Apache ──────────────────────────────────────────────────────────────
echo "[SIA] Starting Apache..."
exec "$@"
