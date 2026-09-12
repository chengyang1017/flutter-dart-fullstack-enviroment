# Flutter Playground 部署指南

> 完整的 Flutter 全栈开发环境 - 开箱即用，无需任何配置

## 📋 目录

- [快速开始](#快速开始)
- [系统要求](#系统要求)
- [本地开发](#本地开发)
- [Docker 部署](#docker-部署)
- [Docker Compose 部署](#docker-compose-部署)
- [生产部署](#生产部署)
- [配置说明](#配置说明)
- [故障排除](#故障排除)
- [常见问题](#常见问题)

---

## 🚀 快速开始

### 最简单的方式 - Docker Compose

```bash
# 1. 克隆项目
git clone https://github.com/chengyang1017/flutter-dart-fullstack-enviroment.git
cd flutter-dart-fullstack-enviroment

# 2. 启动所有服务
docker-compose up -d

# 3. 访问应用
# 打开浏览器访问: http://localhost:8080
```

✅ 就这样！应用已经启动。

---

## 📦 系统要求

### Docker Compose 部署（推荐）

| 要求 | 最低 | 推荐 |
|-----|------|------|
| **内存** | 4GB | 8GB+ |
| **磁盘空间** | 10GB | 20GB+ |
| **CPU** | 2 核心 | 4+ 核心 |
| **Docker** | 20.10+ | 24.0+ |
| **Docker Compose** | 2.0+ | 2.10+ |

### 本地开发环境

```
✓ Flutter SDK (3.24.1 或更新)
✓ Dart SDK (包含在 Flutter 中)
✓ Git
✓ Android Studio (可选)
```

---

## 💻 本地开发

### 安装依赖

```bash
# 安装 Flutter 依赖
flutter pub get

# 获取 Runner 依赖
cd flutter-runner-server
dart pub get
cd ..
```

### 启动 Runner 服务

```bash
# 使用本地 Flutter 环境
cd flutter-runner-server
dart run bin/server.dart
```

Runner 默认启动在 `http://127.0.0.1:8787`

### 启动 Web 应用

在另一个终端中：

```bash
# 方式 1: Web 浏览器
flutter run -d chrome --dart-define=RUNNER_API_URL=http://127.0.0.1:8787

# 方式 2: 启用热重载和所有平台
flutter run --dart-define=RUNNER_API_URL=http://127.0.0.1:8787

# 使用 Mock Runner (无需启动 Runner 服务)
flutter run -d chrome
```

---

## 🐳 Docker 部署

### 单个容器部署

#### 仅应用容器

```bash
# 1. 构建镜像
docker build -t flutter-playground:latest .

# 2. 运行容器
docker run -d \
  --name flutter-app \
  -p 8080:80 \
  -e RUNNER_API_URL=http://flutter-runner:8787 \
  flutter-playground:latest

# 3. 访问应用
# http://localhost:8080
```

#### 仅 Runner 容器

```bash
# 1. 构建 Runner 镜像
docker build \
  -t flutter-practice-runner:local \
  -f flutter-runner-server/docker/Dockerfile \
  flutter-runner-server/docker

# 2. 运行 Runner
docker run -d \
  --name flutter-runner \
  -p 8787:8787 \
  -e RUNNER_EXECUTION_MODE=local \
  -v flutter-pub-cache:/home/runner/.pub-cache \
  flutter-practice-runner:local
```

### 单容器中运行多个服务

这种方式**不推荐**用于生产环境，仅用于测试：

```dockerfile
# 自定义 Dockerfile (all-in-one)
FROM flutter-practice-runner:local

# 安装 nginx
RUN apt-get update && apt-get install -y nginx \
    && rm -rf /var/lib/apt/lists/*

# 复制应用构建...
# (参考 Dockerfile 中的构建步骤)

# 启动脚本
CMD ["/entrypoint.sh"]
```

---

## 🐳 Docker Compose 部署（推荐）

### 快速启动

```bash
# 1. 复制环境配置
cp .env.example .env

# 2. (可选) 编辑 .env 文件
# 按需自定义端口、版本等

# 3. 启动所有服务
docker-compose up -d

# 4. 查看日志
docker-compose logs -f

# 5. 检查状态
docker-compose ps
```

### 常见操作

```bash
# 重启服务
docker-compose restart

# 停止服务
docker-compose stop

# 完全移除所有服务和容器（不删除卷）
docker-compose down

# 删除所有数据（包括卷）
docker-compose down -v

# 查看日志
docker-compose logs -f flutter-app
docker-compose logs -f flutter-runner

# 进入容器调试
docker-compose exec flutter-app sh
docker-compose exec flutter-runner bash
```

---

## 🌐 生产部署

### 推荐架构

```
互联网
  ↓
Reverse Proxy (Nginx / Traefik)
  ↓
┌─────────────────────────────────────────┐
│  Docker Compose                          │
├─────────────────────────────────────────┤
│ ┌─────────────────┐  ┌───────────────┐  │
│ │  flutter-app    │  │ flutter-runner│  │
│ │  (Web UI)       │  │ (Executor)    │  │
│ └─────────────────┘  └───────────────┘  │
└─────────────────────────────────────────┘
```

### Nginx 反向代理配置

```nginx
upstream flutter_app {
    server localhost:8080;
}

upstream flutter_runner {
    server localhost:8787;
}

server {
    listen 443 ssl http2;
    server_name flutter-playground.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # 应用路由
    location / {
        proxy_pass http://flutter_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Runner API 路由 (可选: 如果想要隐藏 Runner)
    location /api/runner/ {
        rewrite ^/api/runner/(.*) /$1 break;
        proxy_pass http://flutter_runner;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    server_name flutter-playground.example.com;
    return 301 https://$server_name$request_uri;
}
```

### Docker Compose 生产配置

```bash
# 使用不同的 compose 文件
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# 配置示例见下文
```

### 生产环境变量

```bash
# .env.production
APP_PORT=8080
RUNNER_PORT=8787
FLUTTER_VERSION=3.24.1
RUNNER_MODE=local

# 性能优化
RUNNER_DOCKER_MEMORY=4096m
RUNNER_DOCKER_CPUS=4
RUNNER_IDLE_MINUTES=60

# 日志
LOG_LEVEL=info
```

---

## ⚙️ 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
|-----|-------|------|
| `APP_PORT` | 8080 | Web 应用端口 |
| `RUNNER_PORT` | 8787 | Runner API 端口 |
| `FLUTTER_VERSION` | 3.24.1 | Flutter 版本 |
| `RUNNER_MODE` | local | 执行模式 (local/docker) |
| `RUNNER_IDLE_MINUTES` | 30 | 会话空闲超时(分钟) |
| `RUNNER_DOCKER_MEMORY` | 1024m | 每个会话内存限制 |
| `RUNNER_DOCKER_CPUS` | 1.0 | 每个会话 CPU 限制 |

### 卷挂载

```yaml
volumes:
  flutter-pub-cache:
    # Dart pub 包缓存，加速构建
```

### 网络配置

- **Flutter App**: 暴露端口 8080
- **Runner**: 暴露端口 8787
- **内部通信**: 通过 Docker 网络 `flutter-network`

---

## 🔧 故障排除

### 应用无法访问 Runner

```bash
# 检查 Runner 是否运行
docker-compose ps

# 查看 Runner 日志
docker-compose logs flutter-runner

# 检查网络连接
docker-compose exec flutter-app curl http://flutter-runner:8787/health
```

### 内存不足

```bash
# 增加 Runner 内存限制
# 编辑 docker-compose.yml 中的 RUNNER_DOCKER_MEMORY

# 清理未使用的 Docker 资源
docker system prune -a
```

### Flutter 构建失败

```bash
# 清理缓存
docker-compose down -v
docker system prune -a

# 重建镜像
docker-compose build --no-cache --pull

# 重新启动
docker-compose up -d
```

### Web 应用崩溃

```bash
# 查看详细日志
docker-compose logs -f flutter-app

# 重启应用
docker-compose restart flutter-app

# 检查 nginx 配置
docker-compose exec flutter-app nginx -t
```

---

## ❓ 常见问题

### Q: 我能在手机上访问吗？

**A:** 可以。需要：
1. 确保主机防火墙允许访问
2. 使用主机 IP 地址而不是 localhost
3. 例如: `http://192.168.1.100:8080`

### Q: 如何更新 Flutter 版本？

**A:** 编辑 `.env` 文件中的 `FLUTTER_VERSION`，然后：
```bash
docker-compose build --no-cache --pull
docker-compose up -d
```

### Q: 我能在生产环境中使用吗？

**A:** 可以，但需要：
1. 使用 HTTPS (通过 Nginx 反向代理)
2. 配置资源限制 (内存/CPU/超时)
3. 启用监控和日志收集
4. 定期更新 Flutter 版本和依赖

### Q: 多用户支持怎么样？

**A:** 当前架构支持并发多用户：
- 每个 Runner 会话隔离
- 资源通过内存/CPU 限制
- 会话通过 ID 管理

未来计划：
- WebSocket 替代轮询，减少延迟
- Redis 会话管理
- 持久化存储支持

### Q: 如何贡献改进？

**A:** 欢迎提交 Issue 和 Pull Request！

---

## 📚 相关资源

- [Flutter 官方文档](https://flutter.dev/docs)
- [Docker 官方文档](https://docs.docker.com/)
- [项目 GitHub](https://github.com/chengyang1017/flutter-dart-fullstack-enviroment)

---

**最后更新**: 2026-09-05
**维护者**: Flutter Playground Team
