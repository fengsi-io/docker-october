#!/bin/sh
set -e

if [ "$*" != "start" ]; then
    docker-php-entrypoint "$@"
    return
fi

#
# when debug, we should wait for db ready.
#
if [ "${APP_DEBUG:=false}" = "true" ]; then
    # wait for db started
    wait4ports -q -s 1 -t 60 database=tcp://"${DB_HOST}":"${DB_PORT}"
fi

#
# octobercms initializing
#
if [ ! -f .INITIALIZED ] && [ -n "${DB_HOST}" ] && [ -n "${DB_PORT}" ]; then

    # database migration and new app key
    php artisan october:up

    # active theme and remove demo data
    [ -n "$THEME" ] && php artisan theme:use "${THEME}"
    php artisan october:fresh

    # storage should always have full permission
    chown -R www-data:www-data /var/www/storage

    # set point
    touch .INITIALIZED && echo "initialization done."
fi

#
# plugin install
#
plugin_count() {
    find "/var/www/plugins" -mindepth 2 -maxdepth 2 -type d | wc -l
}

plugins_count_before=$(plugin_count)

for plugin in $(echo "$PLUGINS" | tr "," " "); do
    october-plugin-install.sh "$plugin"
done

plugins_count_after=$(plugin_count)

if [ "$plugins_count_before" != "$plugins_count_after" ]; then
    # set plugin path permission when new plugin installed
    chown -R www-data:www-data /var/www/plugins || true
    # remove cache after new plugin installed
    php artisan cache:clear
    # and run migration
    php artisan october:up
fi

exec docker-php-entrypoint parent caddy -conf /etc/Caddyfile -log stdout -agree
