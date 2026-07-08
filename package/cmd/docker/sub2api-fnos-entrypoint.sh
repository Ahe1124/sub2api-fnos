#!/bin/sh
set -eu

if [ "${1#-}" != "$1" ]; then
    set -- /app/sub2api "$@"
fi

REDIS_BIND="${REDIS_BIND:-${REDIS_HOST:-127.0.0.1}}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DIR="${REDIS_DATA_DIR:-/app/data/redis}"
REDIS_CONF="${REDIS_DIR}/redis.conf"

mkdir -p /app/data "${REDIS_DIR}"

if [ "$(id -u)" = "0" ]; then
    chown -R sub2api:sub2api /app/data 2>/dev/null || true
fi

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
    if [ -n "${REDIS_PASSWORD:-}" ]; then
        printf 'requirepass %s\n' "${REDIS_PASSWORD}"
    fi
} > "${REDIS_CONF}"

if [ "$(id -u)" = "0" ]; then
    chown sub2api:sub2api "${REDIS_CONF}" 2>/dev/null || true
    su-exec sub2api redis-server "${REDIS_CONF}" &
else
    redis-server "${REDIS_CONF}" &
fi
redis_pid="$!"

cleanup() {
    if [ -n "${app_pid:-}" ]; then
        kill "${app_pid}" 2>/dev/null || true
    fi
    if [ -n "${redis_pid:-}" ]; then
        kill "${redis_pid}" 2>/dev/null || true
        wait "${redis_pid}" 2>/dev/null || true
    fi
}

trap cleanup INT TERM EXIT

i=0
while [ "$i" -lt 30 ]; do
    if REDISCLI_AUTH="${REDIS_PASSWORD:-}" redis-cli -h "${REDIS_BIND}" -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

if [ "$i" -ge 30 ]; then
    echo "[sub2api-fnos] Redis failed to start on ${REDIS_BIND}:${REDIS_PORT}" >&2
    exit 1
fi

if [ "$(id -u)" = "0" ]; then
    su-exec sub2api "$@" &
else
    "$@" &
fi
app_pid="$!"

wait "${app_pid}"
status="$?"
cleanup
exit "${status}"
