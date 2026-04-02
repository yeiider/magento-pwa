FROM webdevops/php-apache:8.3

# Configuración de entorno
ENV WEB_DOCUMENT_ROOT=/app/pub
ENV PHP_MEMORY_LIMIT=2G
ENV PHP_MAX_EXECUTION_TIME=1800

# Instalación de dependencias del sistema y Composer
RUN apt-get update && apt-get install -y \
    libxml2-dev libxslt1-dev libicu-dev libpng-dev libjpeg-dev \
    libwebp-dev libfreetype6-dev libzip-dev libonig-dev \
    git unzip curl \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=2.2.24 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar archivos de composer primero para aprovechar la caché de Docker
COPY composer.json composer.lock ./

# Configurar permisos para que el usuario application pueda instalar dependencias
RUN chown -R application:application /app

# Instalar dependencias de Magento como usuario application
# Nota: Si usas repositorios privados (repo.magento.com), 
# deberás tener un archivo auth.json en la raíz.
USER application
RUN composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader || true

# Volver a root para copiar el resto del código y ajustar permisos finales
USER root
COPY --chown=application:application . /app

RUN mkdir -p /app/var /app/generated /app/pub/static /app/pub/media \
    && chown -R application:application /app/var /app/generated /app/pub/static /app/pub/media \
    && chmod +x /app/docker/init-magento.sh

USER application
