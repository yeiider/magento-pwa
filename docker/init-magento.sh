#!/usr/bin/env bash
set -euo pipefail

cd /app

# Colores para los logs
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Iniciando proceso de configuración de Magento...${NC}"

wait_for_port() {
  local host="$1"
  local port="$2"
  local name="$3"
  local retries="${4:-120}"
  local i=1

  while ! (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; do
    if [ "$i" -ge "$retries" ]; then
      echo "Timeout esperando ${name} (${host}:${port})"
      return 1
    fi
    echo "Esperando ${name} (${host}:${port})... intento ${i}/${retries}"
    i=$((i + 1))
    sleep 2
  done
}

# Esperar a que los servicios estén listos
wait_for_port "${MAGENTO_DB_HOST:-db}" 3306 "MariaDB/MySQL"
wait_for_port "redis" 6379 "Redis"
wait_for_port "rabbitmq" 5672 "RabbitMQ"
wait_for_port "${MAGENTO_OPENSEARCH_HOST:-opensearch}" "${MAGENTO_OPENSEARCH_PORT:-9200}" "OpenSearch"

# Asegurar permisos básicos antes de ejecutar comandos de Magento
echo "Ajustando permisos iniciales..."
mkdir -p var generated pub/static pub/media
chmod -R 777 var generated pub/static pub/media

if ! php bin/magento setup:db:status >/dev/null 2>&1; then
  echo -e "${GREEN}Magento no instalado. Ejecutando setup:install...${NC}"
  php -d memory_limit=2G bin/magento setup:install \
    --base-url="${MAGENTO_BASE_URL}" \
    --db-host="${MAGENTO_DB_HOST}" \
    --db-name="${MYSQL_DATABASE}" \
    --db-user="${MYSQL_USER}" \
    --db-password="${MYSQL_PASSWORD}" \
    --admin-firstname="${MAGENTO_ADMIN_FIRSTNAME}" \
    --admin-lastname="${MAGENTO_ADMIN_LASTNAME}" \
    --admin-email="${MAGENTO_ADMIN_EMAIL}" \
    --admin-user="${MAGENTO_ADMIN_USER}" \
    --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
    --backend-frontname="${MAGENTO_ADMIN_FRONTNAME}" \
    --language="${MAGENTO_LANGUAGE}" \
    --currency="${MAGENTO_CURRENCY}" \
    --timezone="${MAGENTO_TIMEZONE}" \
    --use-rewrites=1 \
    --search-engine=opensearch \
    --opensearch-host="${MAGENTO_OPENSEARCH_HOST}" \
    --opensearch-port="${MAGENTO_OPENSEARCH_PORT}" \
    --amqp-host="rabbitmq" \
    --amqp-port="5672" \
    --amqp-user="${RABBITMQ_DEFAULT_USER}" \
    --amqp-password="${RABBITMQ_DEFAULT_PASS}" \
    --amqp-virtualhost="${RABBITMQ_DEFAULT_VHOST}" \
    --cleanup-database
else
  echo -e "${GREEN}Magento ya instalado. Ejecutando setup:upgrade...${NC}"
  php -d memory_limit=2G bin/magento setup:upgrade
fi

echo -e "${GREEN}Compilando código y desplegando contenido estático...${NC}"
php -d memory_limit=2G bin/magento setup:di:compile
php -d memory_limit=2G bin/magento setup:static-content:deploy -f ${MAGENTO_LOCALES}

echo -e "${GREEN}Configurando Cron de Magento...${NC}"
php bin/magento cron:install

echo -e "${GREEN}Reindexando y limpiando cache...${NC}"
php -d memory_limit=2G bin/magento indexer:reindex
php -d memory_limit=2G bin/magento cache:flush

# Ajuste final de permisos
echo "Ajustando permisos finales..."
chmod -R 777 var generated pub/static pub/media

echo -e "${GREEN}¡Inicialización de Magento finalizada con éxito!${NC}"
