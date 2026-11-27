#!/bin/bash
set -eu

export DEBIAN_FRONTEND=noninteractive

log() { printf '\n==> %s\n' "$*"; }
need() { [ -e "$1" ] || { echo "Chybi $1" >&2; exit 1; }; }

log "Oficialni repozitar Zabbix 8.0 pro Debian 13"
apt-get update -qq
apt-get install -y -qq wget curl ca-certificates gnupg openssl mariadb-server

if ! dpkg -s zabbix-release >/dev/null 2>&1; then
  wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_8.0+debian13_all.deb"
  dpkg -i /tmp/zabbix-release.deb
  rm -f /tmp/zabbix-release.deb
  apt-get update -qq
fi

log "Instalace Zabbix 8.0 serveru, frontendu, Apache a Agenta 2"
apt-get install -y -qq zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent2

log "MariaDB a generovani hesla databaze"
systemctl enable --now mariadb
SECRET_DIR=/var/lib/zabbix-install
install -d -m 700 "$SECRET_DIR"

if [ ! -s "$SECRET_DIR/db-password" ]; then
  umask 077
  openssl rand -hex 24 > "$SECRET_DIR/db-password"
fi
DB_PASSWORD=$(cat "$SECRET_DIR/db-password")

mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
CREATE USER IF NOT EXISTS 'zabbix'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'zabbix'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

if ! mysql -uroot -N -e "SELECT 1 FROM information_schema.tables WHERE table_schema='zabbix' AND table_name='dbversion'" | grep -q 1; then
  log "Prvni import databazoveho schematu Zabbix 8.0"
  mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 1;"
  if [ -f /usr/share/zabbix/sql-scripts/mysql/server.sql.gz ]; then
    zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASSWORD}" zabbix
  else
    zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASSWORD}" zabbix
  fi
  mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"
fi

log "Konfigurace Zabbix serveru a Agenta 2"
SERVER_CONF=/etc/zabbix/zabbix_server.conf
AGENT_CONF=/etc/zabbix/zabbix_agent2.conf
need "$SERVER_CONF"
need "$AGENT_CONF"

sed -i -E '/^[[:space:]#]*(DBHost|DBName|DBUser|DBPassword|Timeout)=/d' "$SERVER_CONF"
cat >> "$SERVER_CONF" <<EOF
DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=${DB_PASSWORD}
Timeout=15
EOF
chown root:zabbix "$SERVER_CONF"
chmod 640 "$SERVER_CONF"

sed -i -E '/^[[:space:]#]*(Server|ServerActive|Hostname|Timeout)=/d' "$AGENT_CONF"
cat >> "$AGENT_CONF" <<'EOF'
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=tenzatebou-zbx8
Timeout=15
EOF

log "PHP a Apache frontend (bez PHP wizardu)"
for dir in /etc/php/*/apache2/conf.d /etc/php/*/cli/conf.d; do
  [ -d "$dir" ] && echo "date.timezone = Europe/Prague" > "$dir/99-zabbix.ini"
done

install -d -m 750 -o www-data -g www-data /etc/zabbix/web
cat > /etc/zabbix/web/zabbix.conf.php <<EOF
<?php
\$DB['TYPE']       = 'MYSQL';
\$DB['SERVER']     = '127.0.0.1';
\$DB['PORT']       = '3306';
\$DB['DATABASE']   = 'zabbix';
\$DB['USER']       = 'zabbix';
\$DB['PASSWORD']   = '${DB_PASSWORD}';
\$DB['SCHEMA']     = '';
\$DB['ENCRYPTION'] = false;
\$ZBX_SERVER        = '127.0.0.1';
\$ZBX_SERVER_PORT   = '10051';
\$ZBX_SERVER_NAME   = 'TenZaTebou - Debian 13 - Zabbix 8';
EOF
chown www-data:www-data /etc/zabbix/web/zabbix.conf.php
chmod 600 /etc/zabbix/web/zabbix.conf.php

systemctl enable mariadb apache2 zabbix-server zabbix-agent2
systemctl restart mariadb apache2 zabbix-server zabbix-agent2

log "Zalozeni monitorovanych hostu pres Zabbix API"
need /tmp/configure-hosts.php
/usr/bin/php /tmp/configure-hosts.php

log "Hotovo: http://127.0.0.1:8080/zabbix"
echo "Heslo Admin je ulozene ve VM v /var/lib/zabbix-install/admin-password (pouze root)."
