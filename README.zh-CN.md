# Flutter Dart 全栈开发环境

这是一个以 Dart / Flutter 为核心的 monorepo，包含 Flutter Workbench、课程管理员后台、远程 Flutter Runner、Workspace 存储服务和 Cloudflare 边缘服务。

## 仓库结构

```text
apps/
  workbench/                 Flutter IDE / Workbench 客户端
  admin/                     Jaspr 管理员后台
services/
  flutter-runner/            远程 Flutter 执行服务
  workspace-storage/         账号、Workspace、课程和管理员 API
  cloudflare-mcp/            Cloudflare MCP 集成
  cloudflare-share-proxy/    公共分享 / 预览代理
infra/
  docker-compose.yml
  docker-compose.prod.yml
  cloudflare/wrangler.toml
scripts/                     本地启动、运行和诊断脚本
docs/                        项目、部署和历史归档文档
```

## 课程数据

Flutter 客户端不再内置生产课程。课程以 Workspace Storage 服务为唯一数据源，由 Jaspr 管理员后台通过管理员课程 API 维护；Workbench 只从 `/content/lessons` 读取已发布课程。

这样新增、修改、翻译课程不再需要修改 Flutter 源码或重新把课程写死进客户端。

## 常用命令

```bash
cd apps/workbench
flutter pub get
flutter test
```

```bash
cd apps/admin
dart pub get
dart analyze
```

```bash
docker compose -f infra/docker-compose.yml up -d
```

Windows Web 开发可运行 `scripts/run-web.ps1`；Android 真机可运行 `scripts/run-android-tablet.ps1`。

## 迁移前备份

本次 monorepo 整理前的完整状态保存在 `backup/pre-monorepo-20260912` 分支。
