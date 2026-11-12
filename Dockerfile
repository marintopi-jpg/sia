FROM php:8.3-apache

# Install required PHP extensions and system packages
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libxml2-dev \
    unzip \
    curl \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
        gd \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        curl \
        mbstring \
        xml \
        opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable Apache modules
RUN a2enmod rewrite headers

# Set recommended PHP.ini settings
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
    echo 'upload_max_filesize=64M'; \
    echo 'post_max_size=64M'; \
    echo 'max_execution_time=300'; \
    echo 'memory_limit=256M'; \
    echo 'session.cookie_httponly=1'; \
    echo 'session.cookie_samesite=Strict'; \
    echo 'display_errors=Off'; \
    echo 'log_errors=On'; \
    echo 'error_log=/var/log/apache2/php_errors.log'; \
} > /usr/local/etc/php/conf.d/sia.ini

# Apache VirtualHost configuration
COPY docker/apache-sia.conf /etc/apache2/sites-available/sia.conf
RUN a2dissite 000-default && a2ensite sia

# Copy application files
COPY . /var/www/html/

# Set correct permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && chmod -R 775 /var/www/html/assets \
    && chmod -R 775 /var/www/html/modules \
    && mkdir -p /var/www/html/tmp \
    && chown www-data:www-data /var/www/html/tmp \
    && chmod 775 /var/www/html/tmp

# Copy and set up entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
