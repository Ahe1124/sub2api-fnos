# syntax=docker/dockerfile:1

FROM redis:8-alpine AS redis

FROM weishaw/sub2api:0.1.152

USER root

RUN apk add --no-cache postgresql16 postgresql16-client postgresql16-contrib su-exec

COPY --from=redis /usr/local/bin/redis-server /usr/local/bin/redis-server
COPY --from=redis /usr/local/bin/redis-cli /usr/local/bin/redis-cli
COPY --from=redis /usr/lib/libssl.so.3 /usr/lib/libssl.so.3
COPY --from=redis /usr/lib/libcrypto.so.3 /usr/lib/libcrypto.so.3
COPY --chmod=755 sub2api-fnos-entrypoint.sh /app/sub2api-fnos-entrypoint.sh

ENTRYPOINT ["/app/sub2api-fnos-entrypoint.sh"]
CMD ["/app/sub2api"]
