#!/bin/bash
lastversion="$(ls -l /var/cache/pacman/pkg/postgres*.tar.xz | grep -v libs | tail -2 | head -1 | awk -F ' ' '{print $NF}')"

systemctl disable postgresql --now

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
su postgres -P -c '/usr/bin/vacuumdb --all --analyze-in-stages'
)

rm -rf /var/lib/postgres/tmp /var/lib/postgres/olddata