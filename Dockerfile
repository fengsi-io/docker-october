#
# caddy builder
#
FROM fengsiio/caddy-builder:v1 as caddy-builder

ARG CADDY_VERSION="1.0.5"
ARG CADDY_PLUGINS="\
    github.com/epicagency/caddy-expires \
    github.com/captncraig/caddy-realip \
    "

RUN if [ -n "${http_proxy}" ]; then \
        go env -w GO111MODULE=on && go env -w GOPROXY=https://goproxy.io,direct; \
    fi && \
    /bin/sh /usr/bin/builder.sh


#
# October CMS Builder
#
FROM composer:2 as october-builder

WORKDIR /build

ARG OCTOBER_VERSION="v1.1.5"

RUN set -ex; \
    composer create-project \
        --quiet \
        --no-dev \
        --no-scripts \
        --ignore-platform-reqs \
        october/october . "${OCTOBER_VERSION#v}"; \
    # for filsystem cache
    composer require --quiet --no-scripts --ignore-platform-reqs league/flysystem-cached-adapter; \
    # use .env mode and backup origin config files
    chmod +x artisan; \
    ./artisan package:discover; \
    ./artisan october:env; \
    mv .env .env.origin && mv config config.origin; \
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
    ) | xargs rm -rf;


#
# Final Stage
#
FROM php:7.4-fpm-alpine
LABEL maintainer "Gavin Luo <gavin.luo@fengsi.io>"
WORKDIR /var/www

RUN set -ex; \
    if [ -n "${http_proxy}" ]; then \
        sed -i 's@https://.*.alpinelinux.org@http://mirrors.aliyun.com@g' /etc/apk/repositories; \
    fi; \
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
    ln -s "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    # for premission and entrypoint depends
    apk add --no-cache wait4ports patch fcgi; \
    chown -R www-data:www-data /var/www; \
    # install composer
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php -r "if (hash_file('sha384', 'composer-setup.php') === '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"; \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer --version=2.0.12; \
    php -r "unlink('composer-setup.php');"; \
    # for init
    mkdir -p /docker-entrypoint.d/plugins;

# Install Caddy & Process Wrapper
COPY --from=caddy-builder /go/bin/parent /bin/parent
COPY --from=caddy-builder /go/bin/caddy /usr/bin/caddy
COPY --from=october-builder --chown=www-data:www-data /build/ ./
COPY ./rootfs/ /
RUN chmod 755 /usr/local/bin/*.sh
ENV PATH="/var/www:${PATH}"
# ignore compose root warmming, ref: https://github.com/mattrayner/docker-lamp/issues/29
ENV COMPOSER_ALLOW_SUPERUSER 1
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=10s --retries=3 CMD [ "php-fpm-healthcheck.sh" ]
ENTRYPOINT [ "docker-entrypoint.sh" ]
CMD [ "start" ]
