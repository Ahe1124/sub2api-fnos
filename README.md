# Sub2API 飞牛安装包

这个目录用于把 [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api) 打包成飞牛 FPK 应用。

安装后只会启动一个 Docker Compose 项目，并且只运行一个容器：

- 容器名：`sub2api`
- 镜像名：`sub2api-fnos:0.1.4`
- 网络模式：host
- 访问端口：`0.0.0.0:8088`

PostgreSQL 和 Redis 已经内嵌到同一个容器里，不会再额外启动数据库或 Redis 容器。所有应用数据、数据库数据、Redis 数据和日志都保存在飞牛所选安装盘的 `@appshare/sub2api-docker/data` 目录中。

安装包会优先拉取 GitHub 容器仓库里的预构建镜像，避免在 NAS 上本地编译。只有预构建镜像拉取失败时才会回退到本地构建。

Windows 本地打包：

```powershell
.\build_sub2api_fpk.ps1
```

打包为拉取预构建镜像的 FPK：

```powershell
.\build_sub2api_fpk.ps1 -Image "ghcr.io/<github-owner-lowercase>/sub2api-fnos:0.1.4"
```

生成的安装包会写入 `dist/sub2api-docker_0.1.4.fpk`。

GitHub Actions：

- 推送这个目录到 GitHub 仓库。
- 在 Actions 页面运行 `Build Sub2API fnOS Image`。
- 工作流会发布 `ghcr.io/<github-owner-lowercase>/sub2api-fnos:0.1.4` 和 `latest`。
- 镜像发布后，用 `-Image` 重新打包 FPK，飞牛安装时就会直接拉预构建镜像。

安装说明：

- Sub2API 监听 `0.0.0.0:8088`。
- PostgreSQL 监听容器内 `127.0.0.1:15432`。
- Redis 监听容器内 `127.0.0.1:16379`。
- 安装向导填写的管理员邮箱和密码会在数据库初始化后强制同步，确保可以直接登录。
- 数据库、Redis、JWT 和 TOTP 密钥会自动生成并保存到 `sub2api.env`。
- 卸载会删除容器、镜像、应用数据、日志、Docker 资源和旧版本可能创建的系统 PostgreSQL 数据库账号。
