#
# caddy builder
#
FROM registry.us-west-1.aliyuncs.com/fengsi/docker-caddy-builder:1.0.0 as caddy-builder

ARG CADDY_VERSION
ARG CADDY_PLUGINS

RUN /bin/sh /usr/bin/builder.sh


#
# October CMS Builder
#
FROM composer as october-builder

WORKDIR /build
ARG OCTOBER_VERSION="master"

RUN set -ex; \
    composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/; \
    # for github proxy support
    composer config -g github-protocols https ssh; \
    # for parallel install
    composer global require hirak/prestissimo;

RUN set -ex; \
    git clone --quiet -b "v${OCTOBER_VERSION}" --depth 1 https://github.com/octobercms/october.git .; \
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
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories; \
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
        # php 7.3
        # --with-png-dir=/usr/include/ \
        # --with-webp-dir=/usr/include/ \
        # --with-jpeg-dir=/usr/include/ \
        # --with-freetype-dir=/usr/include/ \
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
