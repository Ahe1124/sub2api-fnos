#!/bin/sh
set -eu

if [ "${1#-}" != "$1" ]; then
    set -- /app/sub2api "$@"
fi

APP_USER="${APP_USER:-sub2api}"
DATA_DIR="${SUB2API_DATA_DIR:-/app/data}"
LOG_DIR="${DATA_DIR}/logs"

POSTGRES_BIND="${POSTGRES_BIND:-${DATABASE_HOST:-127.0.0.1}}"
POSTGRES_PORT="${POSTGRES_PORT:-${DATABASE_PORT:-15432}}"
POSTGRES_DB="${POSTGRES_DB:-${DATABASE_DBNAME:-sub2api_fnos}}"
POSTGRES_USER="${POSTGRES_USER:-${DATABASE_USER:-sub2api_fnos}}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-${DATABASE_PASSWORD:-}}"
POSTGRES_DATA_DIR="${POSTGRES_DATA_DIR:-${DATA_DIR}/postgresql}"
POSTGRES_RUN_DIR="${POSTGRES_RUN_DIR:-${DATA_DIR}/postgresql-run}"
POSTGRES_LOG="${LOG_DIR}/postgresql.log"

REDIS_BIND="${REDIS_BIND:-${REDIS_HOST:-127.0.0.1}}"
REDIS_PORT="${REDIS_PORT:-16379}"
REDIS_DIR="${REDIS_DATA_DIR:-${DATA_DIR}/redis}"
REDIS_CONF="${REDIS_DIR}/redis.conf"

DATABASE_HOST="${DATABASE_HOST:-${POSTGRES_BIND}}"
DATABASE_PORT="${DATABASE_PORT:-${POSTGRES_PORT}}"
DATABASE_USER="${DATABASE_USER:-${POSTGRES_USER}}"
DATABASE_PASSWORD="${DATABASE_PASSWORD:-${POSTGRES_PASSWORD}}"
DATABASE_DBNAME="${DATABASE_DBNAME:-${POSTGRES_DB}}"
DATABASE_SSLMODE="${DATABASE_SSLMODE:-disable}"

REDIS_HOST="${REDIS_HOST:-${REDIS_BIND}}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_DB="${REDIS_DB:-0}"

JWT_SECRET="${JWT_SECRET:-}"
TOTP_ENCRYPTION_KEY="${TOTP_ENCRYPTION_KEY:-}"

if [ -z "${POSTGRES_PASSWORD}" ]; then
    echo "[sub2api-fnos] DATABASE_PASSWORD or POSTGRES_PASSWORD is required" >&2
    exit 1
fi
if [ -z "${JWT_SECRET}" ]; then
    echo "[sub2api-fnos] JWT_SECRET is required" >&2
    exit 1
fi
if [ -z "${TOTP_ENCRYPTION_KEY}" ]; then
    echo "[sub2api-fnos] TOTP_ENCRYPTION_KEY is required" >&2
    exit 1
fi

as_app() {
    if [ "$(id -u)" = "0" ]; then
        su-exec "${APP_USER}" "$@"
    else
        "$@"
    fi
}

sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

prepare_dirs() {
    mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${POSTGRES_DATA_DIR}" "${POSTGRES_RUN_DIR}" "${REDIS_DIR}"
    chmod 700 "${DATA_DIR}" "${POSTGRES_DATA_DIR}" "${POSTGRES_RUN_DIR}" "${REDIS_DIR}" 2>/dev/null || true
    if [ "$(id -u)" = "0" ]; then
        chown -R "${APP_USER}:${APP_USER}" "${DATA_DIR}" 2>/dev/null || true
    fi
}

configure_postgres_files() {
    sed -i '/sub2api-fnos-runtime-begin/,/sub2api-fnos-runtime-end/d' "${POSTGRES_DATA_DIR}/postgresql.conf" 2>/dev/null || true
    cat >> "${POSTGRES_DATA_DIR}/postgresql.conf" <<EOF_CONF
# sub2api-fnos-runtime-begin
listen_addresses = '${POSTGRES_BIND}'
port = ${POSTGRES_PORT}
unix_socket_directories = '${POSTGRES_RUN_DIR}'
max_connections = 80
shared_buffers = '128MB'
logging_collector = off
log_min_messages = warning
# sub2api-fnos-runtime-end
EOF_CONF

    sed -i '/sub2api-fnos-runtime-begin/,/sub2api-fnos-runtime-end/d' "${POSTGRES_DATA_DIR}/pg_hba.conf" 2>/dev/null || true
    cat >> "${POSTGRES_DATA_DIR}/pg_hba.conf" <<EOF_HBA
# sub2api-fnos-runtime-begin
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
# sub2api-fnos-runtime-end
EOF_HBA
}

init_postgres() {
    if [ ! -s "${POSTGRES_DATA_DIR}/PG_VERSION" ]; then
        rm -rf "${POSTGRES_DATA_DIR:?}/"*
        pwfile="${DATA_DIR}/.postgres-superuser-password"
        printf '%s\n' "${POSTGRES_PASSWORD}" > "${pwfile}"
        chmod 600 "${pwfile}"
        if [ "$(id -u)" = "0" ]; then
            chown "${APP_USER}:${APP_USER}" "${pwfile}" 2>/dev/null || true
        fi
        as_app initdb -D "${POSTGRES_DATA_DIR}" -U postgres --encoding=UTF8 --locale=C --auth-local=trust --auth-host=scram-sha-256 --pwfile="${pwfile}"
        rm -f "${pwfile}"
    fi
    configure_postgres_files
}

start_postgres() {
    init_postgres
    rm -f "${POSTGRES_RUN_DIR}/.s.PGSQL.${POSTGRES_PORT}.lock" 2>/dev/null || true
    as_app pg_ctl -D "${POSTGRES_DATA_DIR}" -l "${POSTGRES_LOG}" -w start
    postgres_started=1

    i=0
    while [ "$i" -lt 60 ]; do
        if as_app pg_isready -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -U postgres >/dev/null 2>&1; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    echo "[sub2api-fnos] PostgreSQL failed to start on ${POSTGRES_BIND}:${POSTGRES_PORT}" >&2
    tail -100 "${POSTGRES_LOG}" >&2 2>/dev/null || true
    exit 1
}

prepare_database() {
    db_password_sql="$(sql_escape "${POSTGRES_PASSWORD}")"
    as_app psql -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
    CREATE ROLE ${POSTGRES_USER} LOGIN PASSWORD '${db_password_sql}';
  ELSE
    ALTER ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${db_password_sql}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER} ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}')\gexec
ALTER DATABASE ${POSTGRES_DB} OWNER TO ${POSTGRES_USER};
GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};
SQL
}

write_app_config() {
    if [ "${SUB2API_WRITE_CONFIG:-true}" != "true" ] && [ -s "${DATA_DIR}/config.yaml" ]; then
        return 0
    fi

    umask 077
    cat > "${DATA_DIR}/config.yaml" <<EOF_CONFIG
server:
    host: ${SERVER_HOST:-0.0.0.0}
    port: ${SERVER_PORT:-8088}
    mode: ${SERVER_MODE:-release}
database:
    host: ${DATABASE_HOST}
    port: ${DATABASE_PORT}
    user: ${DATABASE_USER}
    password: ${DATABASE_PASSWORD}
    dbname: ${DATABASE_DBNAME}
    sslmode: ${DATABASE_SSLMODE}
redis:
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}
    db: ${REDIS_DB}
    enable_tls: ${REDIS_ENABLE_TLS:-false}
jwt:
    secret: ${JWT_SECRET}
    expire_hour: ${JWT_EXPIRE_HOUR:-24}
default:
    user_concurrency: ${DEFAULT_USER_CONCURRENCY:-5}
    user_balance: ${DEFAULT_USER_BALANCE:-0}
    api_key_prefix: ${DEFAULT_API_KEY_PREFIX:-sk-}
    rate_multiplier: ${DEFAULT_RATE_MULTIPLIER:-1}
rate_limit:
    requests_per_minute: ${RATE_LIMIT_REQUESTS_PER_MINUTE:-60}
    burst_size: ${RATE_LIMIT_BURST_SIZE:-10}
timezone: ${TZ:-Asia/Shanghai}
EOF_CONFIG
    if [ "$(id -u)" = "0" ]; then
        chown "${APP_USER}:${APP_USER}" "${DATA_DIR}/config.yaml" 2>/dev/null || true
    fi
}

start_redis() {
    umask 077
    {
        printf 'bind %s\n' "${REDIS_BIND}"
        printf 'protected-mode yes\n'
        printf 'port %s\n' "${REDIS_PORT}"
        printf 'dir %s\n' "${REDIS_DIR}"
        printf 'save 60 1\n'
        printf 'appendonly yes\n'
        printf 'appendfsync everysec\n'
        printf 'loglevel notice\n'
        printf 'databases 16\n'
        if [ -n "${REDIS_PASSWORD}" ]; then
            printf 'requirepass %s\n' "${REDIS_PASSWORD}"
        fi
    } > "${REDIS_CONF}"

    if [ "$(id -u)" = "0" ]; then
        chown "${APP_USER}:${APP_USER}" "${REDIS_CONF}" 2>/dev/null || true
    fi

    as_app redis-server "${REDIS_CONF}" &
    redis_pid="$!"

    i=0
    while [ "$i" -lt 30 ]; do
        if REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_BIND}" -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    echo "[sub2api-fnos] Redis failed to start on ${REDIS_BIND}:${REDIS_PORT}" >&2
    exit 1
}

cleanup() {
    trap - INT TERM EXIT
    if [ -n "${app_pid:-}" ]; then
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
    fi
    if [ -n "${redis_pid:-}" ]; then
        kill "${redis_pid}" 2>/dev/null || true
        wait "${redis_pid}" 2>/dev/null || true
    fi
    if [ "${postgres_started:-0}" = "1" ]; then
        as_app pg_ctl -D "${POSTGRES_DATA_DIR}" -m fast -w stop >/dev/null 2>&1 || true
    fi
}

trap cleanup INT TERM EXIT

prepare_dirs
start_postgres
prepare_database
start_redis
write_app_config

as_app "$@" &
app_pid="$!"

wait "${app_pid}"
status="$?"
cleanup
exit "${status}"
