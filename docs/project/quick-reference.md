# Flutter Playground - 快速参考指南

## 🚀 30 秒快速开始

```bash
git clone https://github.com/chengyang1017/flutter-dart-fullstack-enviroment.git
cd flutter-dart-fullstack-enviroment
docker-compose up -d
# 打开浏览器访问: http://localhost:8080
```

---

## 📦 核心命令速记

### Docker Compose

| 命令 | 说明 |
|------|------|
| `docker-compose up -d` | 启动所有服务 |
| `docker-compose ps` | 查看服务状态 |
| `docker-compose logs -f` | 查看日志 |
| `docker-compose stop` | 停止服务 |
| `docker-compose down` | 删除容器 |
| `docker-compose down -v` | 删除容器和卷 |
| `docker-compose restart` | 重启所有服务 |
| `docker-compose build --no-cache` | 重建镜像 |

### 本地开发

| 命令 | 说明 |
|------|------|
| `flutter pub get` | 获取依赖 |
| `flutter run` | 运行应用 |
| `flutter run -d chrome` | 在浏览器中运行 |
| `flutter analyze` | 代码分析 |
| `flutter test` | 运行测试 |

### Runner 服务

| 命令 | 说明 |
|------|------|
| `cd flutter-runner-server && dart pub get` | 获取 Runner 依赖 |
| `dart run bin/server.dart` | 启动 Runner 服务 |

---

## 🔧 常见任务

### 检查服务是否正常运行

```bash
# 方法 1: 查看状态
docker-compose ps

# 方法 2: 运行诊断脚本
./diagnose.sh

# 方法 3: 访问健康检查
curl http://localhost:8080/health        # Web 应用
curl http://localhost:8787/health        # Runner
```

### 查看日志排查问题

```bash
# 查看所有日志
docker-compose logs

# 只看应用日志
docker-compose logs flutter-app

# 只看 Runner 日志
docker-compose logs flutter-runner

# 实时查看日志
docker-compose logs -f

# 查看最后 100 行
docker-compose logs --tail=100
```

### 更新 Flutter 版本

```bash
# 1. 编辑 .env 文件
# FLUTTER_VERSION=3.24.1  # 改为新版本

# 2. 重建镜像
docker-compose build --no-cache --pull

# 3. 重新启动
docker-compose up -d
```

### 进入容器调试

```bash
# 进入 Web 应用容器
docker-compose exec flutter-app sh

# 进入 Runner 容器
docker-compose exec flutter-runner bash
```

### 清理磁盘空间

```bash
# 删除未使用的 Docker 资源
docker system prune -a

# 只删除容器
docker container prune

# 只删除镜像
docker image prune -a
```

---

## 🌐 服务访问

| 服务 | 地址 | 用途 |
|------|------|------|
| Web 应用 | http://localhost:8080 | Flutter 学习环境 |
| Runner API | http://localhost:8787 | 代码执行引擎 |
| Health Check (App) | http://localhost:8080/health | 应用健康检查 |
| Health Check (Runner) | http://localhost:8787/health | Runner 健康检查 |

---

## 📋 配置文件位置

```
项目根目录/
├── .env                          # 环境变量（运行时）
├── .env.example                  # 环境变量模板
├── docker-compose.yml            # Docker Compose 配置
├── docker-compose.prod.yml       # 生产环境扩展配置
├── Dockerfile                    # Web 应用 Dockerfile
├── docker/
│   ├── Dockerfile                # Runner Dockerfile
│   ├── nginx.conf                # Nginx 主配置
│   └── default.conf              # Nginx 站点配置
└── flutter-runner-server/        # Runner 源代码
```

---

## 🆘 快速故障排查

### 应用无法访问

```bash
# 1. 检查容器运行状态
docker-compose ps

# 2. 查看应用日志
docker-compose logs flutter-app

# 3. 测试连接
curl http://localhost:8080

# 4. 重启应用
docker-compose restart flutter-app
```

### Runner 无响应

```bash
# 1. 检查 Runner 容器
docker-compose logs flutter-runner

# 2. 测试 Runner API
curl http://localhost:8787/health

# 3. 检查内存/CPU
docker stats flutter-runner

# 4. 重启 Runner
docker-compose restart flutter-runner
```

### 构建失败

```bash
# 1. 清理缓存
docker-compose down -v
docker system prune -a

# 2. 重新构建
docker-compose build --no-cache --pull

# 3. 启动
docker-compose up -d
```

---

## 📚 完整文档

- [详细部署指南](DEPLOYMENT.md)
- [Runner 说明](flutter-runner-server/README.md)
- [项目 GitHub](https://github.com/chengyang1017/flutter-dart-fullstack-enviroment)

---

## 💡 提示

- ✅ 首次启动时会自动拉取 Docker 镜像，请确保网络连接良好
- ✅ 使用 `docker-compose logs -f` 可以实时查看所有日志
- ✅ 修改 `.env` 文件后需要重新启动服务
- ✅ 定期运行 `docker system prune` 清理无用资源

---

**最后更新**: 2026-09-05
