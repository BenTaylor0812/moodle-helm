FROM php:8.2-apache

# Install dependencies
RUN apt-get update && apt-get install -y \
    git unzip libpng-dev libjpeg-dev libfreetype6-dev libxml2-dev libzip-dev libicu-dev libonig-dev mariadb-client \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd intl zip mysqli opcache

RUN a2enmod rewrite

# Create directories
RUN mkdir -p /var/www/moodle /var/www/moodledata

# Download Moodle
ARG MOODLE_VERSION=5.1.3
COPY moodle-versions/moodle-${MOODLE_VERSION}.tgz /tmp/moodle.tgz
RUN tar -xz -f /tmp/moodle.tgz -C /var/www/moodle --strip-components=1 \
    && rm /tmp/moodle.tgz

# Apache should serve the public directory
RUN rm -rf /var/www/html && \
    ln -s /var/www/moodle/public /var/www/html

# Permissions
RUN chown -R www-data:www-data /var/www/moodle /var/www/moodledata && \
    chmod -R u+rwX,go+rX /var/www/moodle /var/www/moodledata

RUN printf "max_input_vars = 5000\n" > /usr/local/etc/php/conf.d/moodle.ini

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]