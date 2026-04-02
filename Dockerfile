FROM webdevops/php-apache:8.3

# Configuración de entorno
ENV WEB_DOCUMENT_ROOT=/app/pub
ENV PHP_MEMORY_LIMIT=2G
ENV PHP_MAX_EXECUTION_TIME=1800

# Instalación de dependencias del sistema y Composer
RUN apt-get update && apt-get install -y \
    libxml2-dev libxslt1-dev libicu-dev libpng-dev libjpeg-dev \
    libwebp-dev libfreetype6-dev libzip-dev libonig-dev \
    git unzip curl sudo \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=2.2.24 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar el código del proyecto
COPY . /app

# Crear carpetas y ajustar permisos como root
RUN mkdir -p /app/var /app/generated /app/pub/static /app/pub/media /app/vendor /app/bin \
    && chown -R application:application /app \
    && chmod +x /app/docker/init-magento.sh

# Mantener el contenedor como root para permitir comandos de sistema
# El script de inicio se encargará de ejecutar los comandos de Magento como application
USER root
