#!/usr/bin/env bash
set -euo pipefail

cd /app

# Colores para los logs
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Iniciando proceso de configuración de Magento...${NC}"

# Función para ejecutar comandos como el usuario application
run_as_app() {
  sudo -u application php -d memory_limit=4G "$@"
}

# 1. Sincronización Inteligente (Prioridad GIT)
# Sincronizamos todo desde /app_source (la imagen con el nuevo Git) hacia /app (el volumen)
# EXCLUIMOS las carpetas persistentes/generadas para no borrarlas ni pisarlas.
echo -e "${GREEN}Sincronizando cambios de Git con el volumen...${NC}"
rsync -a --delete \
  --exclude='/var/' \
  --exclude='/generated/' \
  --exclude='/pub/static/' \
  --exclude='/pub/media/' \
  --exclude='/vendor/' \
  /app_source/ /app/

chown -R application:application /app
echo -e "${GREEN}Sincronización completa.${NC}"

# 2. Gestión de Dependencias (Composer)
# Siempre intentamos composer install; si no hay cambios en composer.lock, tardará segundos.
echo -e "${GREEN}Verificando dependencias de Composer...${NC}"
sudo -u application composer config -g parallelism 20 || true
sudo -u application COMPOSER_MEMORY_LIMIT=-1 composer install \
    --no-interaction --no-dev --prefer-dist --optimize-autoloader --no-progress

# 3. Esperar servicios
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

wait_for_port "${MAGENTO_DB_HOST:-db}" 3306 "MySQL"
wait_for_port "redis" 6379 "Redis"
wait_for_port "rabbitmq" 5672 "RabbitMQ"
wait_for_port "${MAGENTO_OPENSEARCH_HOST:-opensearch}" "${MAGENTO_OPENSEARCH_PORT:-9200}" "OpenSearch"

# 4. Ajustar permisos
echo "Ajustando permisos..."
mkdir -p var generated pub/static pub/media vendor
chown -R application:application var generated pub/static pub/media vendor
chmod -R 777 var generated pub/static pub/media

# 5. Instalación o Upgrade
if [ ! -f "app/etc/env.php" ]; then
  echo -e "${GREEN}Ejecutando setup:install con SSL activado...${NC}"
  run_as_app bin/magento setup:install \
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
    --use-secure=1 \
    --base-url-secure="${MAGENTO_BASE_URL}" \
    --use-secure-admin=1 \
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
  echo -e "${GREEN}Magento ya instalado. Aplicando cambios de configuración...${NC}"
  run_as_app bin/magento config:set web/unsecure/base_url "${MAGENTO_BASE_URL}"
  run_as_app bin/magento config:set web/secure/base_url "${MAGENTO_BASE_URL}"
  run_as_app bin/magento config:set web/secure/use_in_frontend 1
  run_as_app bin/magento config:set web/secure/use_in_adminhtml 1
  run_as_app bin/magento setup:upgrade
fi

# 6. Pasos finales
echo -e "${GREEN}Compilando código y desplegando contenido estático...${NC}"
run_as_app bin/magento setup:di:compile
run_as_app bin/magento setup:static-content:deploy -f ${MAGENTO_LOCALES}
run_as_app bin/magento cron:install
run_as_app bin/magento indexer:reindex
run_as_app bin/magento cache:flush

chown -R application:application var generated pub/static pub/media
echo -e "${GREEN}¡Inicialización de Magento finalizada con éxito!${NC}"
