ARG PHP_VERSION=8.2
ARG PHP_IMAGE_TYPE=fpm

FROM php:${PHP_VERSION}-${PHP_IMAGE_TYPE}

LABEL maintainer="Zahedul Hossain <zahedul.hossain@grameenphone.com>"

ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY="localhost,127.0.0.*"
ARG BUILD_MODE="dev"
ARG TIMEZONE="Asia/Dhaka"

ARG APT_DEPENDENCIES="curl zip unzip g++ gettext libz-dev libpq-dev libssl-dev libzip-dev libicu-dev libfreetype6-dev libjpeg-dev libpng-dev libxml2-dev zlib1g-dev openssl uuid-dev vim nginx supervisor"
ARG APT_DEPENDENCIES_REMOVABLE="g++ libxml2-dev"
ARG PHP_DOCKER_EXTENSIONS="bcmath exif fileinfo gd gettext intl opcache pdo pdo_mysql pcntl sockets tokenizer xml xmlreader xmlwriter zip"
ARG PHP_PECL_EXTENSIONS="redis uuid"

# App Root Path relative to context
ARG HOST_APP_ROOT_DIR="./src/"
ARG WORK_DIR="/var/www/html"

# Composer vairables
ARG COMPOSER_HOME="/var/www/.composer"
ARG COMPOSER_VERSION="2.5.4"

# Proxy
ENV http_proxy="${HTTP_PROXY}" \
    https_proxy="${HTTPS_PROXY}" \
    no_proxy="${NO_PROXY}"

# Timezone
ENV TZ="${TIMEZONE}"

# For PHP Extension xmlreader
ENV CFLAGS="-I/usr/src/php"

USER root

RUN echo "-- Configure Timezone --" \
    && echo "${TIMEZONE}" > /etc/timezone \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && echo "-- Install Dependencies --" \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends ${APT_DEPENDENCIES} \
    && echo "-- Install PHP Extensions --" \
    && if [ ! -z "${HTTP_PROXY}" ]; then \
    pear config-set http_proxy "${HTTP_PROXY}" \
    ;fi \
    && pear update-channels \
    # && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-configure intl \
    && docker-php-ext-configure zip \
    && docker-php-ext-install -j$(nproc) ${PHP_DOCKER_EXTENSIONS} \
    && pecl install ${PHP_PECL_EXTENSIONS} \
    && docker-php-ext-enable ${PHP_PECL_EXTENSIONS} \
    && pear clear-cache \
    && echo "-- Cleanup Junks --" \
    && apt-get autoremove -y ${APT_DEPENDENCIES_REMOVABLE} \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && echo "-- Symlink creating --" \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# PHP Composer Installation & Directory Permissions
RUN curl -L -o /usr/local/bin/composer https://github.com/composer/composer/releases/download/${COMPOSER_VERSION}/composer.phar \
    && mkdir -p ${COMPOSER_HOME} \
    && mkdir /run/php \
    && chown -R www-data:www-data ${COMPOSER_HOME} /run/php \
    && chmod -R ugo+w ${COMPOSER_HOME} \
    && chmod -R g+s ${COMPOSER_HOME} \
    && chmod ugo+x /usr/local/bin/composer \
    && composer --version

COPY ./docker/app/php.ini /usr/local/etc/php/conf.d/app-php.ini

# PHP INI Settings for production by default
ENV PHP_INI_OUTPUT_BUFFERING=4096 \
    PHP_INI_MAX_EXECUTION_TIME=60 \
    PHP_INI_MAX_INPUT_TIME=60 \
    PHP_INI_MEMORY_LIMIT="256M" \
    PHP_INI_DISPLAY_ERRORS="Off" \
    PHP_INI_DISPLAY_STARTUP_ERRORS="Off" \
    PHP_INI_POST_MAX_SIZE="2M" \
    PHP_INI_FILE_UPLOADS="On" \
    PHP_INI_UPLOAD_MAX_FILESIZE="2M" \
    PHP_INI_MAX_FILE_UPLOADS="2" \
    PHP_INI_ALLOW_URL_FOPEN="On" \
    PHP_INI_DATE_TIMEZONE="${TIMEZONE}" \
    PHP_INI_SESSION_SAVE_HANDLER="files" \
    PHP_INI_SESSION_SAVE_PATH="/tmp" \
    PHP_INI_SESSION_USE_STRICT_MODE=0 \
    PHP_INI_SESSION_USE_COOKIES=1 \
    PHP_INI_SESSION_USE_ONLY_COOKIES=1 \
    PHP_INI_SESSION_NAME="APP_SSID" \
    PHP_INI_SESSION_COOKIE_SECURE="On" \
    PHP_INI_SESSION_COOKIE_LIFETIME=0 \
    PHP_INI_SESSION_COOKIE_PATH="/" \
    PHP_INI_SESSION_COOKIE_DOMAIN="" \
    PHP_INI_SESSION_COOKIE_HTTPONLY="On" \
    PHP_INI_SESSION_COOKIE_SAMESITE="" \
    PHP_INI_SESSION_UPLOAD_PROGRESS_NAME="APP_UPLOAD_PROGRESS" \
    PHP_INI_OPCACHE_ENABLE=1 \
    PHP_INI_OPCACHE_ENABLE_CLI=0 \
    PHP_INI_OPCACHE_MEMORY_CONSUMPTION=256 \
    PHP_INI_OPCACHE_INTERNED_STRINGS_BUFFER=16 \
    PHP_INI_OPCACHE_MAX_ACCELERATED_FILES=100000 \
    PHP_INI_OPCACHE_MAX_WASTED_PERCENTAGE=25 \
    PHP_INI_OPCACHE_USE_CWD=0 \
    PHP_INI_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_INI_OPCACHE_REVALIDATE_FREQ=0 \
    PHP_INI_OPCACHE_SAVE_COMMENTS=0 \
    PHP_INI_OPCACHE_ENABLE_FILE_OVERRIDE=1 \
    PHP_INI_OPCACHE_MAX_FILE_SIZE=0 \
    PHP_INI_OPCACHE_FAST_SHUTDOWN=1

WORKDIR ${WORK_DIR}

RUN chown -R www-data:www-data /var/www

USER www-data

# Composer Packages Installation
COPY --chown=www-data:www-data ${HOST_APP_ROOT_DIR}composer.* ${WORK_DIR}/
RUN composerInstallArgs="--no-scripts --no-interaction --no-autoloader" \
    && export composerInstallArgs \
    && if [ ${BUILD_MODE} = "prod" ]; then \
    composerInstallArgs="$composerInstallArgs --no-dev" \
    && export composerInstallArgs \
    ;fi \
    && composer install $composerInstallArgs

# App ENV Settings
ENV APP_NAME="Laravel" \
    APP_ENV="local" \
    APP_KEY="base64:7Jra6ji6aWajKgEXtObIc+rRgqp83KIQ0j7PPEe9YLY=" \
    APP_DEBUG="true" \
    APP_URL="http://localhost"

# Composer DumpAutoload
COPY --chown=www-data:www-data ${HOST_APP_ROOT_DIR} ${WORK_DIR}
RUN composerDumpAutoloadArgs="--optimize" \
    && export composerDumpAutoloadArgs \
    && if [ ${BUILD_MODE} = "prod" ]; then \
    composerDumpAutoloadArgs="$composerDumpAutoloadArgs --classmap-authoritative" \
    && export composerDumpAutoloadArgs \
    ;fi \
    && composer dump-autoload $composerDumpAutoloadArgs

RUN chmod -R ug+w storage/logs/

# Web
ENV NGINX_VHOST_ENABLE_HTTP_TRAFFIC="true" \
    NGINX_VHOST_ENABLE_HTTPS_TRAFFIC="true" \
    NGINX_VHOST_SERVER_NAME="_" \
    NGINX_VHOST_HTTP_SERVER_NAME="_" \
    NGINX_VHOST_CLIENT_MAX_BODY_SIZE="2m" \
    NGINX_VHOST_SSL_CERTIFICATE="/etc/ssl/certs/ssl-cert-snakeoil.pem" \
    NGINX_VHOST_SSL_CERTIFICATE_KEY="/etc/ssl/certs/ssl-cert-snakeoil.key"

# Add Nginx Configs
COPY --chown=root:root ./docker/app/php-fpm.conf usr/local/etc/php-fpm.conf
COPY --chown=root:root ./docker/web/includes/*.conf /etc/nginx/includes/
COPY --chown=root:root ./docker/web/nginx.conf /etc/nginx/nginx.conf

# Add Vhost Configs
COPY --chown=root:root ./docker/web/conf.d/vhost-http.conf /etc/nginx/conf.d/default.conf
COPY --chown=root:root ./docker/web/conf.d/vhost-https.conf /etc/nginx/conf.d/default-ssl.conf

# Add Certs
COPY --chown=root:root ./docker/.commons/certs/* /etc/ssl/certs/
COPY --chown=www-data:www-data ./docker/app/docker-entrypoint.sh /usr/local/bin/entrypoint.sh

USER root

# RUN if [ ! -f /etc/ssl/certs/default.crt ]; then \
#     openssl genrsa -out "/etc/ssl/certs/default.key" 4096 \
#     && openssl req -new -key "/etc/ssl/certs/default.key" -out "/etc/ssl/certs/default.csr" -subj "/CN=default/O=default/C=UK" \
#     && openssl x509 -req -days 3072 -in "/etc/ssl/certs/default.csr" -signkey "/etc/ssl/certs/default.key" -out "/etc/ssl/certs/default.crt" \
# ;fi

WORKDIR ${WORK_DIR}

# SUPERVISOR
COPY ./docker/supervisor/supervisord.conf /etc/supervisor/
COPY ./docker/supervisor/conf.d/* /etc/supervisor/conf.d/

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
