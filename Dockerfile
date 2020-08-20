FROM php:7.4-apache

# enable apache modules
RUN a2enmod rewrite headers remoteip

# need gnupg for adding apt repo
RUN apt-get update \
    && apt-get install -y gnupg

# add nodesource
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && npm install -g cross-env

# mysql dep for app
RUN docker-php-ext-install -j$(nproc) pdo_mysql

# OTHER PHP EXTS HERE (and composer ;-))

RUN apt-get update \
    && apt-get install -y zlib1g-dev libzip-dev \
    && docker-php-ext-install -j$(nproc) zip;

# xdebug for dev
ARG debug
RUN  if [ $debug ]; then \
    pecl install xdebug-2.9.0 \
    && docker-php-ext-enable xdebug; \
fi

RUN ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime \
    && echo "Europe/London" > /etc/timezone \
    && echo 'date.timezone=Europe/London' > /usr/local/etc/php/conf.d/settimezone.ini \
    && echo 'xdebug.profiler_enable_trigger=1' > /usr/local/etc/php/conf.d/xdebugprofiler.ini \
    && echo 'zend_extension=opcache' > /usr/local/etc/php/conf.d/opcache.ini \
    && echo 'opcache.enable=1' >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo 'post_max_size = 15M' > /usr/local/etc/php/conf.d/filesize.ini \
    && echo 'upload_max_filesize = 15M' >> /usr/local/etc/php/conf.d/filesize.ini

# grab composer
RUN apt-get update \
    && apt-get install -y git zip unzip
RUN curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer
RUN composer global require hirak/prestissimo

WORKDIR /var/www

# install composer dependencies
COPY composer.json composer.lock ./
RUN if [ $debug ]; then \
    composer install --no-scripts --no-autoloader; \
else \
    composer install --no-scripts --no-autoloader --no-dev; \
fi

RUN if [ $debug ] && [ -f "vendor/codeception/c3/c3.php" ]; then \
    cp vendor/codeception/c3/c3.php ./; \
fi

# build theme
COPY resources ./resources
COPY package.json package-lock.json webpack.mix.js ./
COPY html ./html

RUN npm install && npm run prod

# copy rest of fileset
COPY . .

# generate classmap now extra directories are present
RUN composer dump-autoload --optimize

RUN if [ ! $debug ]; then \
    php artisan route:cache; \
fi

# fix permissions
RUN chown www-data:www-data -R storage bootstrap tests/_output

COPY .docker-contents/apache-logs.conf /etc/apache2/sites-enabled/00-default.conf

COPY .docker-contents/apache-logs.conf /etc/apache2/sites-enabled/00-default.conf

# record version if available
ARG version
RUN if [ $version ]; then \
    echo $version > VERSION; \
fi
