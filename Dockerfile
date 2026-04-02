FROM webdevops/php-apache:8.3

# Configuración de entorno
ENV WEB_DOCUMENT_ROOT=/app/pub
ENV PHP_MEMORY_LIMIT=2G
ENV PHP_MAX_EXECUTION_TIME=1800

# Instalación de dependencias del sistema y Composer
RUN apt-get update && apt-get install -y \
    libxml2-dev libxslt1-dev libicu-dev libpng-dev libjpeg-dev \
    libwebp-dev libfreetype6-dev libzip-dev libonig-dev \
    git unzip curl sudo rsync \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=2.2.24 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar el código del proyecto a DOS lugares:
# 1. /app (donde Portainer montará el volumen)
# 2. /app_source (nuestra fuente de verdad interna)
COPY . /app
COPY . /app_source

# Ajustar permisos
RUN chmod +x /app/docker/init-magento.sh \
    && chmod +x /app_source/docker/init-magento.sh \
    && chown -R application:application /app /app_source

USER root
