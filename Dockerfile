#
# caddy builder
#
FROM fengsiio/caddy-builder:v1 as caddy-builder

ARG CADDY_VERSION="1.0.5"
ARG CADDY_PLUGINS="\
    github.com/epicagency/caddy-expires \
    github.com/captncraig/caddy-realip \
    "

RUN if [ ! -z ${http_proxy+x} ]; then \
        go env -w GO111MODULE=on && go env -w GOPROXY=https://goproxy.io,direct; \
    fi && \
    /bin/sh /usr/bin/builder.sh


#
# October CMS Builder
#
FROM composer:2 as october-builder

WORKDIR /build

ARG OCTOBER_VERSION="v1.1.1"

RUN set -ex; \
    # force to use v1
    composer self-update --1; \
    if [ ! -z ${http_proxy+x} ]; then \
        export HTTP_PROXY_REQUEST_FULLURI=0; \
        export HTTPS_PROXY_REQUEST_FULLURI=0; \
        composer config -g repo.packagist composer https://packagist.phpcomposer.com; \
    fi; \
    composer global require hirak/prestissimo; \
    # get sources
    git clone --quiet -b "${OCTOBER_VERSION}" --depth 1 https://github.com/octobercms/october.git .; \
    # patch https://github.com/octobercms/october/issues/5033
    git config --global url."https://github.com/".insteadOf git@github.com:; \
    git config --global url."https://".insteadOf "git://"; \
    # install package
    composer install -a --no-dev --no-progress --ignore-platform-reqs; \
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
    if [ ! -z ${http_proxy+x} ]; then \
        sed -i 's@dl-cdn.alpinelinux.org@mirrors.aliyun.com@g' /etc/apk/repositories; \
    fi; \
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

# install configs and scripts
COPY --chown=www-data:www-data ./rootfs/ /

# for docker-entrypoint.sh support
RUN set -ex; \
    apk add --no-cache acl patch fcgi; \
    setfacl -Rdm g:www-data:rwx /var/www; \
    chmod +x /*.sh;

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=10s --retries=3 CMD [ "/php-fpm-healthcheck.sh" ]

ENTRYPOINT [ "/bin/sh", "/docker-entrypoint.sh" ]
CMD [ "/bin/parent", "caddy", "-conf", "/etc/Caddyfile", "-log", "stdout", "-agree" ]
