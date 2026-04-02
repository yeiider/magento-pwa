FROM webdevops/php-apache:8.3

# Configuración de entorno
ENV WEB_DOCUMENT_ROOT=/app/pub
ENV PHP_MEMORY_LIMIT=2G
ENV PHP_MAX_EXECUTION_TIME=1800

# Instalación de dependencias del sistema necesarias para Magento
RUN apt-get update && apt-get install -y \
    libxml2-dev \
    libxslt1-dev \
    libicu-dev \
    libpng-dev \
    libjpeg-dev \
    libwebp-dev \
    libfreetype6-dev \
    libzip-dev \
    libonig-dev \
    git \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copiar el código del proyecto al contenedor
COPY --chown=application:application . /app

# Ajustar permisos para el usuario de la aplicación
RUN chmod +x /app/docker/init-magento.sh \
    && mkdir -p /app/var /app/generated /app/pub/static /app/pub/media \
    && chown -R application:application /app/var /app/generated /app/pub/static /app/pub/media

WORKDIR /app

USER application
