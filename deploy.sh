#!/bin/bash
# ============================================
# 万悟平台 - Ubuntu 服务器部署脚本
# 用法: ./deploy.sh <命令>
# ============================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---- 配置 ----
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE=".env"
ENV_IMAGE_FILE=".env.image.amd64"
ENV_ONTOLOGY_FILE=".env.ontology"

# Git 远程名称（服务器上 origin 已指向局域网 Git 仓库；本机如用 internal 可自行修改）
GIT_REMOTE="${GIT_REMOTE:-origin}"
GIT_BRANCH="custom"

# ---- 检查环境 ----
check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker 未安装，请先执行: sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    fi
    if ! docker compose version &>/dev/null; then
        err "docker compose 插件未安装，请执行: sudo apt-get install -y docker-compose-plugin"
    fi
    if ! docker network inspect wanwu-net &>/dev/null; then
        log "创建 Docker 网络 wanwu-net..."
        docker network create wanwu-net
    fi
    # 检查内存
    local mem_gb
    mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -lt 16 ]; then
        warn "内存仅 ${mem_gb}GB，建议 32GB+。可关闭非核心服务节省内存。"
    fi
}

# ---- 拉取最新代码 ----
pull_latest() {
    log "拉取最新代码 (remote=$GIT_REMOTE, branch=$GIT_BRANCH)..."
    cd "$PROJECT_DIR"
    git fetch "$GIT_REMOTE"
    git checkout "$GIT_BRANCH"
    git pull "$GIT_REMOTE" "$GIT_BRANCH"
    log "当前 commit: $(git log --oneline -1)"
}

# ---- 构建前端镜像 ----
build_frontend() {
    log "构建前端镜像..."
    cd "$PROJECT_DIR"
    # 优先使用项目自带的 Dockerfile.frontend；不复制 .bak 覆盖
    if [ ! -f Dockerfile.frontend ]; then
        err "缺少 Dockerfile.frontend（仅构建 aibase 前端的定制 Dockerfile）"
    fi
    docker build -f Dockerfile.frontend \
        -t wanwu-frontend:custom .
    log "前端镜像构建完成: wanwu-frontend:custom"
}

# ---- 构建后端镜像 ----
build_backend() {
    log "构建后端镜像..."
    cd "$PROJECT_DIR"
    docker build -f Dockerfile.backend \
        --build-arg WANWU_ARCH=amd64 \
        -t wanwu-backend:custom .
    log "后端镜像构建完成: wanwu-backend:custom"
}

# ---- 启动服务 ----
start_services() {
    log "启动所有服务..."
    cd "$PROJECT_DIR"
    docker compose \
        --env-file "$ENV_FILE" \
        --env-file "$ENV_ONTOLOGY_FILE" \
        --env-file "$ENV_IMAGE_FILE" \
        up -d
    log "服务启动完成"
    echo ""
    echo "============================================"
    echo "  访问地址: http://$(grep WANWU_EXTERNAL_IP "$ENV_FILE" | cut -d= -f2):$(grep WANWU_EXTERNAL_PORT "$ENV_FILE" | cut -d= -f2)"
    echo "  默认账号: admin / Wanwu123456"
    echo "============================================"
}

# ---- 停止服务 ----
stop_services() {
    log "停止所有服务..."
    cd "$PROJECT_DIR"
    docker compose \
        --env-file "$ENV_FILE" \
        --env-file "$ENV_ONTOLOGY_FILE" \
        --env-file "$ENV_IMAGE_FILE" \
        down
    log "服务已停止"
}

# ---- 重启服务 ----
restart_services() {
    stop_services
    start_services
}

# ---- 查看日志 ----
show_logs() {
    cd "$PROJECT_DIR"
    docker compose logs -f --tail=100 "${@:-}"
}

# ---- 查看状态 ----
show_status() {
    cd "$PROJECT_DIR"
    echo ""
    echo "========== 容器状态 =========="
    docker compose ps 2>/dev/null || echo "无运行中的容器"
    echo ""
    echo "========== 资源使用 =========="
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true
}

# ---- 首次部署（初始化 .env） ----
init() {
    log "初始化环境配置..."
    cd "$PROJECT_DIR"

    if [ ! -f .env ]; then
        cp .env.example .env
        log "已创建 .env，请编辑配置后重新运行"
        echo ""
        echo "必须修改的配置项:"
        echo "  WANWU_EXTERNAL_IP=<你的服务器公网IP>"
        echo "  WANWU_BFF_JWT_SIGNING_KEY=<随机字符串>"
        echo ""
        echo "编辑完成后执行: ./deploy.sh first-start"
        exit 0
    fi

    if [ ! -f .env.ontology ]; then
        cp .env.ontology.example .env.ontology
    fi

    # 生成 RSA 密钥目录
    mkdir -p project/rsa/login-rsa project/rsa/oauth-rsa

    log "环境初始化完成"
}

# ---- 首次启动 ----
first_start() {
    log "首次启动（拉取镜像 + 初始化数据库）..."
    cd "$PROJECT_DIR"

    check_docker

    # 先启动 MySQL
    log "Step 1/4: 启动 MySQL..."
    docker compose --env-file "$ENV_FILE" --env-file "$ENV_IMAGE_FILE" up -d mysql
    sleep 5

    # 初始化数据库
    log "Step 2/4: 初始化数据库..."
    docker compose --env-file "$ENV_FILE" --env-file "$ENV_IMAGE_FILE" up mysql-setup
    sleep 2

    # 启动 Redis + MinIO + Kafka + ES
    log "Step 3/4: 启动中间件..."
    docker compose --env-file "$ENV_FILE" --env-file "$ENV_IMAGE_FILE" up -d redis minio kafka es-setup es

    # 等待 ES 就绪
    log "等待 Elasticsearch 启动..."
    sleep 30

    # 启动所有服务
    log "Step 4/4: 启动全部服务..."
    docker compose \
        --env-file "$ENV_FILE" \
        --env-file "$ENV_ONTOLOGY_FILE" \
        --env-file "$ENV_IMAGE_FILE" \
        up -d

    log "首次启动完成！等待 30 秒后访问..."
    sleep 30
    show_status
}

# ---- 完整部署 ----
deploy() {
    check_docker
    pull_latest
    build_frontend
    build_backend
    restart_services
    sleep 10
    show_status
}

# ---- 仅前端更新 ----
frontend_only() {
    check_docker
    pull_latest
    build_frontend
    cd "$PROJECT_DIR"
    # 重启 nginx 使前端生效
    docker compose \
        --env-file "$ENV_FILE" \
        --env-file "$ENV_ONTOLOGY_FILE" \
        --env-file "$ENV_IMAGE_FILE" \
        restart nginx
    log "前端更新完成"
}

# ---- 查看帮助 ----
show_help() {
    echo "万悟平台 - 部署脚本"
    echo ""
    echo "用法: ./deploy.sh <命令>"
    echo ""
    echo "首次部署流程:"
    echo "  init         初始化 .env 配置文件"
    echo "  first-start  首次启动（拉镜像 + 初始化数据库）"
    echo ""
    echo "日常更新:"
    echo "  deploy       拉代码 + 构建前端 + 重启"
    echo "  frontend-only 仅更新前端（改UI时用）"
    echo "  pull         仅拉取最新代码"
    echo ""
    echo "运维操作:"
    echo "  start        启动所有服务"
    echo "  stop         停止所有服务"
    echo "  restart      重启所有服务"
    echo "  status       查看容器状态和资源使用"
    echo "  logs [服务名] 查看日志（如: ./deploy.sh logs bff-service）"
    echo ""
    echo "构建:"
    echo "  build-frontend 构建前端镜像"
    echo "  build-backend  构建后端镜像"
}

# ---- 主入口 ----
case "${1:-help}" in
    init)            init ;;
    first-start)     first_start ;;
    deploy)          deploy ;;
    frontend-only)   frontend_only ;;
    pull)            pull_latest ;;
    build-frontend)  check_docker && build_frontend ;;
    build-backend)   check_docker && build_backend ;;
    start)           check_docker && start_services ;;
    stop)            check_docker && stop_services ;;
    restart)         check_docker && restart_services ;;
    status)          show_status ;;
    logs)            shift; show_logs "$@" ;;
    help|--help|-h)  show_help ;;
    *)               show_help; exit 1 ;;
esac