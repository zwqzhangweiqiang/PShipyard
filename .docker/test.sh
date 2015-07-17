#!/bin/bash
APP_COMPONENTS="$*"
APP_DIR=/root/shipyard
ADMIN_PASS=${ADMIN_PASS:-}
DEBUG=${DEBUG:-True}
CELERY_WORKERS=${CELERY_WORKERS:-4}
REDIS_HOST=${REDIS_HOST:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}
DB_TYPE=${DB_TYPE:-sqlite3}
DB_NAME=${DB_NAME:-shipyard.db}
DB_USER=${DB_USER:-}
DB_PASS=${DB_PASS:-}
DB_HOST=${DB_HOST:-}
DB_PORT=${DB_PORT:-}
VE_DIR=/opt/ve/shipyard
EXTRA_CMD=${EXTRA_CMD:-}
EXTRA_REQUIREMENTS=${EXTRA_REQUIREMENTS:-}
CONFIG=$APP_DIR/shipyard/local_settings.py
UPDATE_APP=${UPDATE_APP:-}
REVISION=${REVISION:-master}
LOG_DIR=/var/log/shipyard
HIPACHE_CONFIG=/etc/hipache.config.json
HIPACHE_WORKERS=${HIPACHE_WORKERS:-5}
HIPACHE_MAX_SOCKETS=${HIPACHE_MAX_SOCKETS:-100}
HIPACHE_DEAD_BACKEND_TTL=${HIPACHE_DEAD_BACKEND_TTL:-30}
HIPACHE_HTTP_PORT=${HIPACHE_HTTP_PORT:-80}
HIPACHE_HTTPS_PORT=${HIPACHE_HTTPS_PORT:-443}
HIPACHE_SSL_CERT=${HIPACHE_SSL_CERT:-}
HIPACHE_SSL_KEY=${HIPACHE_SSL_KEY:-}
NGINX_RESOLVER=${NGINX_RESOLVER:-`cat /etc/resolv.conf | grep ^nameserver | head -1 | awk '{ print $2; }'`}
SUPERVISOR_CONF=/opt/supervisor.conf

echo "App Components: ${APP_COMPONENTS}"

# check for db link
if [ ! -z "$DB_PORT_5432_TCP_ADDR" ] ; then
    DB_TYPE=postgresql_psycopg2
    DB_NAME="${DB_ENV_DB_NAME:-shipyard}"
    DB_USER="${DB_ENV_DB_USER:-shipyard}"
    DB_PASS="${DB_ENV_DB_PASS:-shipyard}"
    DB_HOST="${DB_PORT_5432_TCP_ADDR}"
    DB_PORT=${DB_PORT_5432_TCP_PORT}
fi
# check for redis link
if [ ! -z "$REDIS_PORT_6379_TCP_ADDR" ] ; then
    REDIS_HOST="${REDIS_PORT_6379_TCP_ADDR:-$REDIS_HOST}"
    REDIS_PORT=${REDIS_PORT_6379_TCP_PORT:-$REDIS_PORT}
fi
cd $APP_DIR
echo "REDIS_HOST=\"$REDIS_HOST\"" > $CONFIG
echo "REDIS_PORT=$REDIS_PORT" >> $CONFIG
cat << EOF > $APP_DIR/.docker/nginx.conf
daemon off;
worker_processes  1;
error_log $LOG_DIR/nginx_error.log;

events {
  worker_connections 1024;
}

http {
  server {
    listen 8000;
    access_log $LOG_DIR/nginx_access.log;

    location / {
      proxy_pass http://127.0.0.1:5000;
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /console/ {
      resolver $NGINX_RESOLVER;

      set \$target '';
      rewrite_by_lua '
        local session_id = " "
        local match, err = ngx.re.match(ngx.var.uri, "(/console/(?<id>.*)/)")
        if match then
            session_id = match["id"]
        else
            if err then
                ngx.log(ngx.ERR, "error: ", err)
                return
            end
            ngx.say("url malformed")
        end

        local key = "console:" .. session_id

        local redis = require "resty.redis"
        local red = redis:new()

        red:set_timeout(1000) -- 1 second

        local ok, err = red:connect("$REDIS_HOST", $REDIS_PORT)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect to redis: ", err)
            return ngx.exit(500)
        end

        local console, err = red:hmget(key, "host", "path")
        if not console then
            ngx.log(ngx.ERR, "failed to get redis key: ", err)
            return ngx.exit(500)
        end

        if console == ngx.null then
            ngx.log(ngx.ERR, "no console session found for key ", key)
            return ngx.exit(400)
        end

        ngx.var.target = console[1]
        
        ngx.req.set_uri(console[2])
      ';
 
      
      proxy_pass http://\$target;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_read_timeout 7200s;
    }
  }
}
EOF
