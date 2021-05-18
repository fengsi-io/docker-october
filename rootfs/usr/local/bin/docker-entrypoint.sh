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
plugin_root_path="/var/www/plugins"
preset_plugins_path="/docker-entrypoint.d/plugins"
new_plugin_installed=false

# install preset plugins
current_dir=$(pwd)
for d in "$preset_plugins_path"/*/*/; do
    plugin_dir=$(echo "$d" | cut -d/ -f4-5)

    if [ "$plugin_dir" = "*/*" ]; then
        continue
    fi

    plugin_name=$(echo "${plugin_dir}" | awk -F '/' '{printf("%s.%s", toupper(substr($1,0,1))substr($1,2,length($1)), toupper(substr($2,0,1))substr($2,2,length($2)))}')

    echo "install preset plugin: \"$plugin_name\""

    plugin_src_path="$preset_plugins_path/$plugin_dir"
    plugin_dest_path="$plugin_root_path/$plugin_dir"

    # Install dependencies if necessary
    if [ -f "$plugin_src_path/composer.json" ]; then
        printf "\tinstall dependencies."
        cd "$plugin_src_path" && composer up && cd "$current_dir"
    fi

    # remove files if path is exist.
    if [ ! -d "$plugin_dest_path" ]; then
        rm -rf "$plugin_dest_path"
    fi

    # create path plugin parent path
    if [ ! -d "$plugin_dest_path" ]; then
        mkdir --parents "$plugin_dest_path"
    fi

    # Install plugin
    cp -r "$plugin_src_path"/* "$plugin_dest_path"
    rm -rf "$plugin_src_path"

    new_plugin_installed=true
done

for plugin in $(echo "$PLUGINS" | tr "," " "); do
    if [ "${plugin#*/}" != "$plugin" ]; then 
        # install package as a composer package
        echo "install composer plugin: \"$plugin\""
        composer require --quiet "$plugin"
        new_plugin_installed=true
    else
        # install plugins from OctoberCMS marketplace
        echo "install marketplace plugin: \"$plugin\""
        plugin_path=$(echo "$plugin" | tr '[:upper:]' '[:lower:]' | tr '.' '/')
        plugin_full_path="/var/www/plugins/$plugin_path"
        set +e
        if [ ! -d "$plugin_full_path" ]; then
            php artisan plugin:install -q "${plugin}"
            new_plugin_installed=true
        fi
        set -e
    fi
done

# set plugin path permission when new plugin installed
if $new_plugin_installed; then
    chown -R www-data:www-data /var/www/plugins || true
fi

#
# apply patches
#
patchs_dir="/var/patches"

if [ -d "$patchs_dir" ]; then

    echo "patchs founded"

    patchfile="/tmp/fengsi.patch"
    diff -ur /var/www $patchs_dir >$patchfile || true
    patch -p3 <$patchfile || true
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

exec docker-php-entrypoint parent caddy -conf /etc/Caddyfile -log stdout -agree
