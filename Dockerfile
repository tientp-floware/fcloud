FROM php:7.4.5-fpm

RUN apt-get update
RUN apt-get install -y vim curl git supervisor nginx nginx-extras \
 zlib1g-dev libpng-dev \
 libicu-dev libxslt-dev libzip-dev memcached libmemcached-tools

# entrypoint.sh and cron.sh dependencies
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        rsync \
        bzip2 \
        busybox-static \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    \
    mkdir -p /var/spool/cron/crontabs; \
    echo '*/5 * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data

RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libevent-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libldap2-dev \
        libmcrypt-dev \
        libmemcached-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libmagickwand-dev \
        libzip-dev \
        libwebp-dev \
        libgmp-dev \
    ; \
    \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        ldap \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        zip \
        gmp \
    ; \
    \
# pecl will claim success even if one install fails, so we need to perform each install separately
    pecl install APCu-5.1.20; \
    pecl install memcached-3.1.5; \
    pecl install redis-5.3.4; \
    pecl install imagick-3.4.4; \
    \
    docker-php-ext-enable \
        apcu \
        memcached \
        redis \
        imagick \
    ; \
    rm -r /tmp/pear; \
    \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/server_tuning.html#enable-php-opcache
RUN mkdir /var/www/html/data; \
    chown -R www-data:root /var/www/html; \
    chmod -R g=u /var/www/html/


RUN curl https://getcomposer.org/download/$(curl -s https://api.github.com/repos/composer/composer/releases/latest | grep 'tag_name' | cut -d '"' -f 4)/composer.phar -o /usr/local/bin/composer && chmod +x /usr/local/bin/composer
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini
ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf

## Debug
RUN pecl install xdebug
## Sync permission
RUN usermod -u 1000 www-data
RUN echo "opcache.enable=1" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini && \
    echo "opcache.preload_user=www-data" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini && \
    echo "opcache.preload=/var/www/html/lib/private/AppFramework/App.php" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini && \
    echo 'max_execution_time = 120s' > /usr/local/etc/php/conf.d/docker-php-maxexectime.ini && \
    echo "cgi.fix_pathinfo=0" > ${php_vars} &&\
    echo "upload_max_filesize = 512M"  >> ${php_vars} &&\
    echo "post_max_size = 512M"  >> ${php_vars} &&\
    echo "variables_order = \"EGPCS\""  >> ${php_vars} && \
    echo "memory_limit = 512M"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 8/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 8/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 3/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 8/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}

COPY conf/nginx-site.conf /etc/nginx/conf.d/
COPY conf/nginx-site-ssl.conf /etc/nginx/conf.d/
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/ssl /etc/letsencrypt
RUN ls /etc/letsencrypt/
COPY conf/supervisord.conf /etc/supervisord.conf
COPY scripts/start.sh /start.sh

COPY src/composer.json src/composer.lock /var/www/html/
RUN composer install
COPY ./src /var/www/html
ARG GIT_REV
LABEL "flo.git_rev"=$GIT_REV
RUN chown -R www-data:www-data /var/www/html/config /var/www/html/apps-extra \
    /var/www/html/data /var/www/html/apps && chmod +x /start.sh
RUN chmod +x /start.sh;
RUN service memcached start
CMD ["/start.sh"]
