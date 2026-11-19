# php-patched: PHP 7.4 is EOL and docker-library no longer publishes patched
# images, so the php binary is rebuilt in-place from official sources only:
#   - base:    docker.io/library/php:7.4-fpm-alpine (official image)
#   - source:  php.net php-7.4.33.tar.xz, fetched from $PHP_URL and verified against
#              $PHP_SHA256 (pinned by the official docker-library/php 7.4 recipe at
#              b9f17156020c3aef71df681b27684533529347a7)
#              built with the image's own `php-config --configure-options`
#   - patch:   full diff of the official emergency backport branch, vendored in
#              patches/ and checksum-verified; upstream source:
#              https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619
#              (tip 712e60f9edfd03f0960fc4fc3c2c375f42b90aa2, which backports the
#              CVE-2026-109618 / CVE-2026-109619 fixes announced on the
#              php.net 2026-10-21 security page)
# Everything outside the rebuild (php.ini, php-fpm config, docker-php-* helpers,
# enabled-extension ini files) stays untouched from the official image.
# Drop this stage once October CMS runs on a supported PHP 8.x release line.
FROM php:7.4-fpm-alpine as php-patched

COPY patches/ /tmp/php-patches/

RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        # needed to apply the backport patch
        patch \
        # runtime deps of the official configure options
        argon2-dev \
        coreutils \
        curl-dev \
        gnu-libiconv-dev \
        libsodium-dev \
        libxml2-dev \
        linux-headers \
        oniguruma-dev \
        openssl-dev \
        readline-dev \
        sqlite-dev \
    ; \
    \
# make sure musl's iconv doesn't get used (https://www.php.net/manual/en/intro.iconv.php)
    rm -vf /usr/include/iconv.h; \
# PHP < 8 doesn't know to look deeper for GNU libiconv: https://github.com/php/php-src/commit/b480e6841ecd5317faa136647a2b8253a4c2d0df
# libcharset/localcharset symlinks from the base image's own build may already exist hence -f
    ln -svf /usr/include/gnu-libiconv/*.h /usr/include/; \
    \
# verify the vendored official backport patch
    cd /tmp/php-patches; \
    sha256sum -c SHA256SUMS; \
    cd /; \
    \
# fetch the official 7.4.33 release source and verify it against the sha pinned by the official docker-library recipe (also present in $PHP_SHA256)
    curl -fsSL -o /tmp/php-src.tar.xz "$PHP_URL"; \
    echo "$PHP_SHA256 */tmp/php-src.tar.xz" | sha256sum -c -; \
    \
# unpack the release source and apply the official backport patch
    rm -rf /usr/src/php; \
    mkdir -p /usr/src/php; \
    tar -xJf /tmp/php-src.tar.xz --strip-components=1 -C /usr/src/php; \
    cd /usr/src/php; \
# keep the release version constants; the official diff rewrites them to branch-dev constants
    cp main/php_version.h /tmp/main-php_version.h; \
    patch --batch --fuzz=0 -p1 < /tmp/php-patches/CVE-2026-109618-109619.patch; \
    cp /tmp/main-php_version.h main/php_version.h; \
    rm -f /tmp/main-php_version.h; \
    \
# reconfigure with the exact options the official image was built with (minus its previous arch records)
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    opts="$(php-config --configure-options | sed -e 's/--build=[^ ]*//' -e 's/build_alias=[^ ]*//')"; \
    export CFLAGS="$PHP_CFLAGS"; \
    export CPPFLAGS="$PHP_CPPFLAGS"; \
    export LDFLAGS="$PHP_LDFLAGS"; \
    ./configure --build="$gnuArch" $opts; \
    \
    make -j "$(nproc)"; \
    find -type f -name '*.a' -delete; \
    make install; \
    \
# strip installed binaries, same as the official recipe
    find /usr/local -type f -perm '/0111' -exec sh -euxc ' \
        strip --strip-all "$@" || : \
    ' -- '{}' + \
    ; \
    make distclean; \
    \
# repack the patched source so october-base's docker-php-ext-install builds extensions against it (docker-php-source extracts with --strip-components=1, top-level dir name is irrelevant)
    tar -cJf /usr/src/php.tar.xz -C /usr/src php; \
    rm -rf /usr/src/php /tmp/php-patches /tmp/php-src.tar.xz; \
    \
# keep the runtime libs the rebuilt binaries link against, then drop build deps (official image flow)
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .php-backport-rundeps $runDeps; \
    apk del .build-deps; \
    \
# smoke test
    php -v; \
    php-config --version; \
    php-fpm -t

FROM php-patched as october-base
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
    # for init
    mkdir -p /docker-entrypoint.d/plugins;

# install composer
COPY --from=composer:2.2.21 /usr/bin/composer /usr/bin/composer

#
# October CMS Builder
#
FROM october-base as october-builder

WORKDIR /build

ARG OCTOBER_VERSION="v1.1.12"
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN set -ex; \
    composer config --global --no-plugins allow-plugins.composer/installers true; \
    composer create-project --quiet --no-dev october/october . "${OCTOBER_VERSION/v/}"; \
    # for filsystem cache
    composer require --quiet league/flysystem-cached-adapter:1.1.*; \
    # use .env mode and backup origin config files
    chmod +x artisan; \
    ./artisan package:discover; \
    ./artisan october:env; \
    mv .env .env.origin && mv config config.origin; \
    cp -r storage storage.origin; \
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
# Nginx
#
# Alpine 3.16（php:7.4 base 所用的发行版）只提供 nginx 1.22.1，且该分支已 EOL、不再接收
# 安全更新；1.22.1 落在多个 CVE 的受影响区间内（如 CVE-2026-125283 try_files+alias、
# CVE-2026-42533 map+regex、CVE-2026-42945 rewrite）。php 7.4 把 Alpine 版本钉死了，
# 无法靠升级基础镜像拿到新版 nginx，因此从源码编译 1.31.9。
# configure 参数刻意对齐 Alpine 的 nginx 包布局（/etc/nginx、/usr/sbin/nginx、
# /var/lib/nginx、/run/nginx），这样 rootfs 里的 http.d/default.conf 与 entrypoint 的
# nginx -g / nginx -s quit 都不需要改。
FROM october-base AS nginx-builder
ARG NGINX_VERSION=1.31.9
ARG NGINX_SHA256=a11c5eeee2e257f4478f0e649f84b0040787d277d2d3e5233952aa6b6dcb80ad
RUN set -ex; \
    apk add --no-cache --virtual .nginx-build-deps \
        gcc musl-dev make pcre2-dev zlib-dev openssl-dev linux-headers curl tar; \
    curl -fsSL -o /tmp/nginx.tar.gz "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  /tmp/nginx.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/nginx-src; \
    tar -xf /tmp/nginx.tar.gz -C /tmp/nginx-src --strip-components=1; \
    cd /tmp/nginx-src; \
    ./configure \
        --prefix=/var/lib/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx/nginx.pid \
        --lock-path=/run/nginx/nginx.lock \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --http-client-body-temp-path=/var/lib/nginx/tmp/client_body \
        --http-proxy-temp-path=/var/lib/nginx/tmp/proxy \
        --http-fastcgi-temp-path=/var/lib/nginx/tmp/fastcgi \
        --http-uwsgi-temp-path=/var/lib/nginx/tmp/uwsgi \
        --http-scgi-temp-path=/var/lib/nginx/tmp/scgi \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-threads \
        --with-pcre-jit \
        --with-cc-opt="-O2"; \
    make -j"$(nproc)"; \
    make install; \
    rm -rf /tmp/nginx-src /tmp/nginx.tar.gz; \
    apk del .nginx-build-deps

#
# Final Stage
#
FROM october-base

# Install Nginx
# 包负责目录布局（/etc/nginx/nginx.conf、http.d/、/var/lib/nginx）与 libssl/zlib；
# 二进制就地替换成上面编译的 1.31.9。pcre2 必须显式安装：Alpine 的 nginx 包依赖的是
# PCRE1(pcre)，而 1.31 默认链接 libpcre2-8，漏了会在启动时报找不到共享库。
RUN apk add --no-cache nginx pcre2
COPY --from=nginx-builder /usr/sbin/nginx /usr/sbin/nginx
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
