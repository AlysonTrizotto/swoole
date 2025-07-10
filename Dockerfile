# Here we are going to install PHP extension requirements that did not come
# with the default PHP container. This will be necessary for Laravel and Swoole.
FROM php:8.3-cli-alpine AS php-base
    WORKDIR /srv/swoole-project

    RUN apk add --no-cache --virtual php_dependencies $PHPIZE_DEPS && \
        apk add --no-cache libstdc++ brotli-dev && \
        docker-php-ext-install bcmath ctype pdo_mysql pcntl && \
        pecl install swoole && \
        docker-php-ext-enable swoole && \
        apk del php_dependencies && \
        rm -rf /var/www && \
        chown -R www-data:www-data /srv/swoole-project

# This stage is so that we can build up everything that doesn't require Laravel
# so AS to not bust the caching for those items.
FROM php-base AS octane-base
    # This really shouldn't be modified, so we aren't advertising the env variable.
    # It allows us to globally install chokidar without modifying the Laravel package.json.
    ENV NODE_PATH="/home/www-data/.npm-global/lib/node_modules"

    RUN apk add --no-cache nodejs npm && \
        mkdir "/home/www-data/.npm-global/" && \
        npm config set prefix "/home/www-data/.npm-global/" && \
        npm install -g chokidar

# Here we have a build container so that it is not necessary to pull composer into
# the final container. We are going to create a new Laravel project and install Octane.
FROM php-base AS laravel
    ARG LARAVEL_VERSION="12.*"

    COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

    COPY . /srv/swoole-project
    COPY composer.json composer.lock /srv/swoole-project/

    RUN cd /srv && \
        cd /srv/swoole-project && \
        composer install --no-dev --no-interaction --prefer-dist && \
        composer require laravel/octane && \
        php artisan octane:install --server="swoole" && \
        php artisan optimize

# This is our final container. We will copy over our built version of Laravel.
FROM octane-base
    USER www-data

    COPY --from=laravel --chown=www-data:www-data /srv/swoole-project/ /srv/swoole-project/

    # Allow the user to specify Swoole options via ENV variables.
    ENV SWOOLE_MAX_REQUESTS=500
    ENV SWOOLE_TASK_WORKERS=auto
    ENV SWOOLE_WATCH=false
    ENV SWOOLE_WORKERS=auto

    # Expose the ports that Octane is using.
    EXPOSE 8000

    # Run Swoole
    CMD ["sh", "-c", "if [[ -z \"$SWOOLE_WATCH\" ]]; then \
            php artisan octane:start --server='swoole' --host='0.0.0.0' --workers=${SWOOLE_WORKERS} --task-workers=${SWOOLE_TASK_WORKERS} --max-requests=${SWOOLE_MAX_REQUESTS}; \
        else \
            php artisan octane:start --server='swoole' --host='0.0.0.0' --workers=${SWOOLE_WORKERS} --task-workers=${SWOOLE_TASK_WORKERS} --max-requests=${SWOOLE_MAX_REQUESTS} --watch; \
        fi"]


    # Check the health status using the Octane status command.
    HEALTHCHECK CMD php artisan octane:status --server="swoole"
