#!/bin/sh
set -e

#
# when debug, we should wait for db ready.
#
if $APP_DEBUG; then
    # wait for db started
    /bin/sh /usr/local/bin/wait-for "${DB_HOST}":"${DB_PORT}" -t 60 -- \
        echo "database ready."
fi

#
# octobercms initializing
#
first_initialize=false

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
    first_initialize=true
fi

#
# plugin install
#
new_plugin_installed=false

for plugin in $(echo "$PLUGINS" | tr "," " "); do

    plugin_path="/var/www/plugins/$(echo "$plugin" | tr '[:upper:]' '[:lower:]' | tr '.' '/')"

    if [ ! -d "$plugin_path" ]; then
        php artisan plugin:install "${plugin}"
        new_plugin_installed=true
    fi
done

if $new_plugin_installed; then
    # set plugin path permission when new plugin installed
    chown -R www-data:www-data /var/www/plugins || true
fi

#
# apply patches
#
patchs_dir="/var/patches"

if [ -d "$patchs_dir" ]; then

    echo "patchs founded"

    patchfile="/tmp/fengsi.patch"
    diff -ur /var/www $patchs_dir > $patchfile || true
    patch -p3 < $patchfile || true
    rm -rf $patchs_dir $patchfile || true
fi

#
# We should clear cache if first install or new plugin installed
#
if $first_initialize || $new_plugin_installed; then
    php artisan cache:clear
fi

# and run migration
php artisan october:up

exec /usr/local/bin/docker-php-entrypoint "$@"
