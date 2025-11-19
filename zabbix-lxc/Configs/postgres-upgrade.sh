#!/bin/bash
set -euo pipefail

lastversion="$(ls -l /var/cache/pacman/pkg/postgres*.tar.xz | grep -v libs | tail -2 | head -1 | awk -F ' ' '{print $NF}')"

systemctl disable postgresql --now || true

mv /var/lib/postgres/data /var/lib/postgres/olddata
mkdir /var/lib/postgres/data /var/lib/postgres/tmp

cp "$lastversion" /var/lib/postgres/tmp
chown -R postgres:postgres /var/lib/postgres/data /var/lib/postgres/tmp

(
cd /var/lib/postgres/tmp || exit
tar xf postgres*.tar.xz
su postgres -P -c 'initdb --locale=en_GB.UTF-8 -E UTF8 -D /var/lib/postgres/data'
su postgres -P -c 'pg_upgrade -b /var/lib/postgres/tmp/usr/bin -B /usr/bin -d /var/lib/postgres/olddata -D /var/lib/postgres/data'
systemctl enable postgresql --now
su postgres -P -c 'reindexdb -d template1; reindexdb -d postgres; reindexdb -d zabbix'
systemctl stop zabbix-server-pgsql || true
su postgres -P -c 'psql -U postgres -c "\
    ALTER DATABASE template1 REFRESH COLLATION VERSION; \
    ALTER DATABASE postgres REFRESH COLLATION VERSION; \
    ALTER DATABASE zabbix REFRESH COLLATION VERSION;"'
su postgres -P -c '/usr/bin/vacuumdb --all --analyze-in-stages'
systemctl start zabbix-server-pgsql
)

rm -rf /var/lib/postgres/tmp /var/lib/postgres/olddata