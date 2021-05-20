#!/bin/sh
set -e

plugin_install_composer() {
    plugin=$*
    echo "install composer plugin: \"$plugin\""
    composer require --quiet "$plugin"
}

plugin_install_marketplace() {
    plugin=$*
    echo "install marketplace plugin: \"$plugin\""
    plugin_path=$(echo "$plugin" | tr '[:upper:]' '[:lower:]' | tr '.' '/')
    plugin_full_path="/var/www/plugins/$plugin_path"
    set +e
    if [ ! -d "$plugin_full_path" ]; then
        php artisan plugin:install -q "${plugin}"
    fi
    set -e
}

plugin_install() {
    plugin=$*
    if echo "$plugin" | grep -qE "^\w+/\w+$"; then
        plugin_install_composer "$plugin"
    elif echo "$plugin" | grep -qE "^[A-Z]\w*.[A-Z]\w*$"; then
        plugin_install_marketplace "$plugin"
    fi
}

if [ "$*" != "" ]; then
    initial_path=$(pwd)
    plugin_install "$*" || true
    cd "$initial_path"
fi
