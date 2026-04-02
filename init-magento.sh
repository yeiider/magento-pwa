#!/usr/bin/env bash
set -euo pipefail

cd /app

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

wait_for_port "${MAGENTO_DB_HOST:-db}" 3306 "MySQL"
wait_for_port "redis" 6379 "Redis"
wait_for_port "rabbitmq" 5672 "RabbitMQ"
wait_for_port "${MAGENTO_OPENSEARCH_HOST:-opensearch}" "${MAGENTO_OPENSEARCH_PORT:-9200}" "OpenSearch"

if ! php bin/magento setup:db:status >/dev/null 2>&1; then
  echo "Magento no instalado. Ejecutando setup:install..."
  php -d memory_limit=2G bin/magento setup:install \
    --base-url="${MAGENTO_BASE_URL:-http://localhost:8088/}" \
    --db-host="${MAGENTO_DB_HOST:-db}" \
    --db-name="${MAGENTO_DB_NAME:-magento}" \
    --db-user="${MAGENTO_DB_USER:-magento}" \
    --db-password="${MAGENTO_DB_PASSWORD:-magento}" \
    --admin-firstname="${MAGENTO_ADMIN_FIRSTNAME:-Admin}" \
    --admin-lastname="${MAGENTO_ADMIN_LASTNAME:-User}" \
    --admin-email="${MAGENTO_ADMIN_EMAIL:-admin@example.com}" \
    --admin-user="${MAGENTO_ADMIN_USER:-admin}" \
    --admin-password="${MAGENTO_ADMIN_PASSWORD:-Admin123!}" \
    --backend-frontname="${MAGENTO_ADMIN_FRONTNAME:-admin}" \
    --language="${MAGENTO_LANGUAGE:-es_CO}" \
    --currency="${MAGENTO_CURRENCY:-USD}" \
    --timezone="${MAGENTO_TIMEZONE:-America/Bogota}" \
    --use-rewrites=1 \
    --search-engine=opensearch \
    --opensearch-host="${MAGENTO_OPENSEARCH_HOST:-opensearch}" \
    --opensearch-port="${MAGENTO_OPENSEARCH_PORT:-9200}" \
    --amqp-host="rabbitmq" \
    --amqp-port="5672" \
    --amqp-user="magento" \
    --amqp-password="magento" \
    --amqp-virtualhost="/"
else
  echo "Magento ya instalado. Se omite setup:install."
fi

echo "Ejecutando comandos de despliegue..."
php -d memory_limit=2G bin/magento setup:upgrade
php -d memory_limit=2G bin/magento setup:di:compile
php -d memory_limit=2G bin/magento setup:static-content:deploy -f ${MAGENTO_LOCALES:-en_US es_ES es_CO}
php -d memory_limit=2G bin/magento indexer:reindex
php -d memory_limit=2G bin/magento cache:flush

echo "Inicializacion Magento finalizada."
