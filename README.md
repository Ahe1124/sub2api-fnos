# Sub2API fnOS package

This directory contains a fnOS Docker FPK wrapper for [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api).

The package starts one Docker Compose project with host networking and exactly one container:

- `sub2api` from a local wrapper image named `sub2api-fnos:0.1.0`

The wrapper image can be pulled from a prebuilt registry image. If no registry image is configured, the install callback builds it locally from `weishaw/sub2api:latest` plus Redis binaries from `redis:8-alpine`. Redis runs inside the same container as a local process, not as a second Docker container.

PostgreSQL is not packaged as a container. The install callback reuses the system PostgreSQL service and creates an isolated `sub2api_fnos` database plus `sub2api_fnos` login role. Persistent application and Redis data is stored under the fnOS app share `sub2api-docker`.

Build on Windows:

```powershell
.\build_sub2api_fpk.ps1
```

Build an FPK that pulls a prebuilt GHCR image:

```powershell
.\build_sub2api_fpk.ps1 -Image "ghcr.io/<github-owner-lowercase>/sub2api-fnos:0.1.0"
```

The generated package is written to `dist/sub2api-docker_0.1.1.fpk`.

GitHub Actions:

- Push this directory to a GitHub repository.
- Run `Build Sub2API fnOS Image` from the Actions tab.
- The workflow publishes `ghcr.io/<github-owner-lowercase>/sub2api-fnos:0.1.0` and `ghcr.io/<github-owner-lowercase>/sub2api-fnos:latest`.
- After the image exists, rebuild the FPK with `-Image` so fnOS installs by pulling the prebuilt image instead of building on the NAS.

Install notes:

- Sub2API listens on `0.0.0.0:8088`.
- Redis runs inside the `sub2api` container and binds only to `127.0.0.1:6379`.
- Database, Redis, JWT and TOTP secrets are generated automatically and stored in `sub2api.env`.
- Uninstall always removes containers, local wrapper image, app share data, the PostgreSQL database, the PostgreSQL role, and the added `pg_hba.conf` block.
