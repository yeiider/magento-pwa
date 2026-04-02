#!/usr/bin/env bash
set -euo pipefail

cd /app

# Colores para los logs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Iniciando proceso de configuración de Magento...${NC}"

# Función para ejecutar comandos como el usuario application
run_as_app() {
  sudo -u application php "$@"
}

# 1. Verificar si vendor o bin/magento existen. Si no, correr composer install.
if [ ! -f "bin/magento" ]; then
  echo -e "${GREEN}Magento no encontrado (bin/magento ausente). Instalando dependencias con Composer...${NC}"
  # Ejecutar como usuario application para evitar problemas de permisos
  sudo -u application composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader
else
  echo -e "${GREEN}Dependencias de Composer ya presentes.${NC}"
fi

# 2. Esperar servicios (DB, Redis, etc)
wait_for_port() {
  local host="$1"
  local port="$2"
  local name="$3"
  local i=1
  while ! (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; do
    if [ "$i" -ge 120 ]; then return 1; fi
    echo "Esperando ${name} (${host}:${port})... $i/120"
    i=$((i + 1))
    sleep 2
  done
}

wait_for_port "${MAGENTO_DB_HOST:-db}" 3306 "MariaDB/MySQL"
wait_for_port "redis" 6379 "Redis"
wait_for_port "rabbitmq" 5672 "RabbitMQ"
wait_for_port "${MAGENTO_OPENSEARCH_HOST:-opensearch}" "${MAGENTO_OPENSEARCH_PORT:-9200}" "OpenSearch"

# 3. Ajustar permisos
echo "Ajustando permisos iniciales..."
mkdir -p var generated pub/static pub/media vendor
chown -R application:application var generated pub/static pub/media vendor bin
chmod -R 777 var generated pub/static pub/media

# 4. Instalación o Upgrade
if ! run_as_app bin/magento setup:db:status >/dev/null 2>&1; then
  echo -e "${GREEN}Ejecutando setup:install...${NC}"
  run_as_app -d memory_limit=2G bin/magento setup:install \
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
  run_as_app -d memory_limit=2G bin/magento setup:upgrade
fi

# 5. Pasos finales
echo -e "${GREEN}Compilando código y desplegando contenido estático...${NC}"
run_as_app -d memory_limit=2G bin/magento setup:di:compile
run_as_app -d memory_limit=2G bin/magento setup:static-content:deploy -f ${MAGENTO_LOCALES}
run_as_app bin/magento cron:install
run_as_app -d memory_limit=2G bin/magento indexer:reindex
run_as_app -d memory_limit=2G bin/magento cache:flush

chown -R application:application var generated pub/static pub/media
echo -e "${GREEN}¡Inicialización de Magento finalizada con éxito!${NC}"
