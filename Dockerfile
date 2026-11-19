# syntax=docker/dockerfile:1
#
# Moodle 5.3 (MOODLE_503_STABLE) application image: Apache + PHP 8.4.
# Requirements come from public/admin/environment.xml (PHP >= 8.3, PostgreSQL >= 17).
# The Moodle source in this repo is baked into the image; only moodledata and the
# database are persistent state.

FROM php:8.4-apache-bookworm

# ---- System libraries + PHP extensions -------------------------------------
# Compiled into the official image already: ctype curl dom fileinfo filter hash iconv
# json mbstring openssl pcre simplexml spl sodium tokenizer xml xmlreader xmlwriter zlib.
# ghostscript + poppler-utils: PDF annotation / conversion (assignment feedback).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
        ghostscript poppler-utils \
        libicu-dev libzip-dev libpq-dev libxml2-dev \
        libpng-dev libjpeg-dev libfreetype6-dev libwebp-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl zip soap exif pgsql opcache; \
    a2enmod remoteip headers deflate expires rewrite; \
    rm -rf /var/lib/apt/lists/*; \
    # Fail the build early if a required extension is missing.
    for ext in iconv mbstring curl openssl ctype zip zlib gd simplexml spl pcre dom xml \
               xmlreader intl json hash fileinfo sodium filter pgsql exif soap tokenizer; do \
        php -m | grep -qix "$ext" || { echo "Missing PHP extension: $ext"; exit 1; }; \
    done

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ---- PHP + Apache configuration ---------------------------------------------
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/php-moodle.ini /usr/local/etc/php/conf.d/zz-moodle.ini
COPY docker/apache/ports.conf /etc/apache2/ports.conf
COPY docker/apache/moodle.conf /etc/apache2/sites-available/000-default.conf
COPY docker/apache/tuning.conf /etc/apache2/conf-available/moodle-tuning.conf
RUN a2enconf moodle-tuning

# Port Apache listens on inside the container (Traefik/Dokploy: 80) and worker cap.
ENV APACHE_PORT=80 \
    APACHE_MAX_REQUEST_WORKERS=40

# ---- Moodle source ------------------------------------------------------------
WORKDIR /var/www/html

# Dependencies first so this layer is cached unless composer.json/lock change.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN composer dump-autoload --no-dev --classmap-authoritative --no-interaction

# Container-specific config.php (reads everything from environment variables) + helper scripts.
COPY docker/config.php /var/www/html/config.php
COPY docker/entrypoint.sh /usr/local/bin/docker-moodle-entrypoint
COPY docker/moodle-cron.sh /usr/local/bin/moodle-cron
COPY docker/moodle-db-check.php /usr/local/bin/moodle-db-check.php
RUN chmod +x /usr/local/bin/docker-moodle-entrypoint /usr/local/bin/moodle-cron; \
    mkdir -p /var/www/moodledata; chown www-data:www-data /var/www/moodledata

VOLUME /var/www/moodledata

ENTRYPOINT ["docker-moodle-entrypoint"]
CMD ["apache2-foreground"]
