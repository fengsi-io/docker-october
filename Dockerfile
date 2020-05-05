#
# caddy builder
#
FROM fengsiio/caddy-builder:v1 as caddy-builder

ARG CADDY_VERSION="1.0.5"
ARG CADDY_PLUGINS="\
    github.com/epicagency/caddy-expires \
    github.com/captncraig/caddy-realip \
    "

RUN /bin/sh /usr/bin/builder.sh


#
# October CMS Builder
#
FROM composer as october-builder

WORKDIR /build

RUN composer global require hirak/prestissimo;

ARG OCTOBER_VERSION="v1.0.465"

RUN set -ex; \
    git clone --quiet -b "${OCTOBER_VERSION}" --depth 1 https://github.com/octobercms/october.git .; \
    # fix compose install hanging
    composer require \
            --no-update \
            --ignore-platform-reqs\
            --optimize-autoloader \
            --classmap-authoritative \
            --apcu-autoloader \
            laravel/framework:5.5.*; \
    # install package
    composer install \
        --no-dev \
        --no-interaction \
        --ignore-platform-reqs \
        --optimize-autoloader \
        --classmap-authoritative \
        --apcu-autoloader \
    ; \
    # remove some useless files
    (\
        find . -type d -name ".git" && \
        find . -type d -name ".github" && \
        find . -name ".gitattributes" && \
        find . -name ".gitignore" && \
        find . -name ".gitmodules" && \
        find . -name ".editorconfig" && \
        find . -name ".babelrc" && \
        find . -name ".jshintrc" && \
        find . -name "phpcs.xml" && \
        find . -name "phpunit.xml" \
    ) | xargs rm -rf; \
    \
    php artisan october:env; \
    # remove origin config files
    mv .env .env.origin; \
    mv config config.origin;


#
# Final Stage
#
FROM php:7.4-fpm-alpine
LABEL maintainer "Gavin Luo <gavin.luo@fengsi.io>"
WORKDIR /var/www

RUN set -ex; \
    # install wait-for command
    (cd /usr/local/bin && curl -O https://raw.githubusercontent.com/eficode/wait-for/master/wait-for); \
    rm -rf *; \
    #
    # PHP
    #
    # install php extensions
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        # depends by ext gd
        libpng-dev \
        libwebp-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        # depends by ext zip
        libzip-dev \
    ; \
    docker-php-ext-configure gd \
        # php 7.4+
        --with-freetype \
        --with-jpeg \
        --with-webp \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        pdo_mysql \
        gd \
        zip \
        opcache \
    ; \
    \
    # keep php run depends and delete build depends
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
        )"; \
    apk add --virtual .phpexts-rundeps $runDeps; \
    apk del .build-deps; \
    # Use the default production configuration
    ln -s "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini";


# Install Caddy & Process Wrapper
COPY --from=caddy-builder /go/bin/parent /bin/parent
COPY --from=caddy-builder /go/bin/caddy /usr/bin/caddy

# install octobercms
COPY --chown=www-data:www-data --from=october-builder /build /var/www

RUN set -ex; \
    apk add --no-cache acl; \
    setfacl -Rdm g:www-data:rwx /var/www

COPY --chown=www-data:www-data ./rootfs/ /

EXPOSE 80

ENTRYPOINT [ "/bin/sh", "/usr/local/bin/docker-entrypoint.sh" ]
CMD [ "/bin/parent", "caddy", "-conf", "/etc/Caddyfile", "-log", "stdout", "-agree" ]
