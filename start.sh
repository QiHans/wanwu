#!/bin/bash
# ============================================
#  Wanwu Platform - Ubuntu Launcher
#  Usage: ./start.sh              Docker mode
#         ./start.sh dev          Local dev mode
#         ./start.sh stop         Stop all
#         ./start.sh status       Show status
#         ./start.sh logs <svc>   View logs
# ============================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}[STEP]${NC} $*"; }

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE=".env"
ENV_IMAGE_FILE=".env.image.amd64"
ENV_ONTOLOGY_FILE=".env.ontology"

# ==========================================
# Docker mode
# ==========================================
start_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker not installed. Run: sudo apt-get install docker-ce docker-compose-plugin"
    fi

    cd "$PROJECT_DIR"

    if ! docker network inspect wanwu-net &>/dev/null 2>&1; then
        log "Creating docker network wanwu-net..."
        docker network create wanwu-net
    fi

    if [ ! -f .env ]; then
        cp .env.example .env
        warn "Created .env from template. Edit it first:"
        echo "  vi .env"
        echo "  Then re-run: ./start.sh"
        exit 1
    fi
    [ ! -f .env.ontology ] && cp .env.ontology.example .env.ontology

    step "Starting all Docker services..."
    docker compose \
        --env-file "$ENV_FILE" \
        --env-file "$ENV_ONTOLOGY_FILE" \
        --env-file "$ENV_IMAGE_FILE" \
        up -d

    sleep 10

    local ip port
    ip=$(grep -oP 'WANWU_EXTERNAL_IP=\K.*' "$ENV_FILE" | head -1)
    port=$(grep -oP 'WANWU_EXTERNAL_PORT=\K.*' "$ENV_FILE" | head -1)

    echo ""
    echo "============================================"
    echo "  URL:     http://${ip}:${port}"
    echo "  Account: admin / Wanwu123456"
    echo "============================================"
}

# ==========================================
# Local dev mode
# ==========================================
start_dev() {
    cd "$PROJECT_DIR"
    mkdir -p project/logs project/rsa/login-rsa project/rsa/oauth-rsa

    step "1/4 Fixing config for local dev..."
    fix_dev_config

    step "2/4 Building Go services..."
    build_services

    step "3/4 Starting Go microservices..."
    start_go_services

    step "4/4 Starting frontend..."
    start_frontend

    echo ""
    echo "============================================"
    echo "  Frontend: http://localhost:8080/aibase/"
    echo "  API:      http://localhost:8088/v1/"
    echo "  Account:  admin / Wanwu123456"
    echo "============================================"
}

fix_dev_config() {
    local changed=0
    for f in configs/microservice/*/configs/config.yaml; do
        [ ! -f "$f" ] && continue
        local tmp
        tmp=$(mktemp)
        sed \
            -e 's|bff-service:6668|localhost:8088|g' \
            -e 's|iam-service:8888|localhost:8888|g' \
            -e 's|model-service:8989|localhost:8989|g' \
            -e 's|mcp-service:9898|localhost:9898|g' \
            -e 's|app-service:9988|localhost:9988|g' \
            -e 's|operate-service:9797|localhost:9797|g' \
            -e 's|channel-service:9990|localhost:9990|g' \
            -e 's|assistant-service:8890|localhost:8890|g' \
            -e 's|agent-service:8990|localhost:8990|g' \
            -e 's|knowledge-service:8889|localhost:8889|g' \
            -e 's|rag-service:9640|localhost:9640|g' \
            -e 's|workflow-wanwu:8999|localhost:8999|g' \
            -e 's|rag-wanwu:8681|localhost:8681|g' \
            -e 's|rag-wanwu:10891|localhost:10891|g' \
            -e 's|rag-wanwu:15000|localhost:15000|g' \
            -e 's|elastic-wanwu:9200|localhost:9200|g' \
            -e 's|minio-wanwu:9000|localhost:9000|g' \
            -e 's|https://localhost:9200|http://localhost:9200|g' \
            -e 's|/app/tmp/rsa|project/rsa|g' \
            "$f" > "$tmp"
        if ! cmp -s "$f" "$tmp"; then
            mv "$tmp" "$f"
            changed=1
        else
            rm -f "$tmp"
        fi
    done
    [ $changed -eq 1 ] && log "Config fixed for local dev" || log "Config already OK"
}

build_services() {
    command -v go &>/dev/null || err "Go not installed"

    mkdir -p bin
    local services=(
        "iam-service" "model-service" "mcp-service" "app-service"
        "operate-service" "channel-service" "assistant-service"
        "agent-service" "knowledge-service" "bff-service"
    )

    for svc in "${services[@]}"; do
        if [ ! -f "bin/${svc}" ] || [ "cmd/${svc}" -nt "bin/${svc}" ]; then
            log "  Building ${svc}..."
            go build -mod vendor -o "bin/${svc}" "./cmd/${svc}" || err "Build failed: ${svc}"
        else
            log "  ${svc} (cached)"
        fi
    done
}

start_go_services() {
    local services=(
        "iam-service" "model-service" "mcp-service" "app-service"
        "operate-service" "channel-service" "assistant-service"
        "agent-service" "knowledge-service"
    )

    for svc in "${services[@]}"; do
        log "  ${svc}..."
        case $svc in
            agent-service|knowledge-service|model-service)
                nohup "./bin/${svc}" > "project/logs/${svc}.log" 2>&1 &
                ;;
            *)
                nohup "./bin/${svc}" -config "configs/microservice/${svc}/configs/config.yaml" \
                    > "project/logs/${svc}.log" 2>&1 &
                ;;
        esac
        sleep 1
    done

    log "  Waiting 10s..."
    sleep 10

    # BFF last
    log "  bff-service (API gateway)..."
    nohup "./bin/bff-service" -config "configs/microservice/bff-service/configs/config.yaml" \
        > "project/logs/bff-service.log" 2>&1 &
    sleep 5

    # Quick health check
    local failed=0
    for f in project/logs/*.log; do
        [ ! -f "$f" ] && continue
        if grep -qi "FATAL\|panic" "$f" 2>/dev/null; then
            local svc; svc=$(basename "$f" .log)
            warn "  ${svc}: $(tail -1 "$f")"
            failed=1
        fi
    done
    [ $failed -eq 0 ] && log "  All services OK"
}

start_frontend() {
    if [ ! -d web/node_modules ]; then
        log "Installing frontend dependencies..."
        (cd web && pnpm install) || err "pnpm install failed"
    fi
    log "  Starting frontend on :8080..."
    cd web
    nohup npx vue-cli-service serve --port 8080 > ../project/logs/frontend.log 2>&1 &
    cd "$PROJECT_DIR"
}

# ==========================================
# Stop
# ==========================================
stop_all() {
    log "Stopping all Wanwu services..."

    for svc in bff-service iam-service model-service mcp-service app-service \
               operate-service channel-service assistant-service agent-service \
               knowledge-service; do
        pkill -f "bin/${svc}" 2>/dev/null && echo "  Stopped: ${svc}" || true
    done

    if command -v docker &>/dev/null; then
        cd "$PROJECT_DIR"
        docker compose --env-file "$ENV_FILE" --env-file "$ENV_ONTOLOGY_FILE" \
            --env-file "$ENV_IMAGE_FILE" down 2>/dev/null || true
        echo "  Stopped: Docker containers"
    fi

    log "Done"
}

# ==========================================
# Status
# ==========================================
show_status() {
    echo ""
    echo "========== Wanwu Services =========="
    echo ""
    check_port() { ss -tlnp 2>/dev/null | grep -q ":${1} " && echo -e "  ${GREEN}[OK]${NC} ${2} :${1}" || echo -e "  ${RED}[--]${NC} ${2} :${1}"; }
    check_port 3306 "MySQL      "
    check_port 6379 "Redis      "
    check_port 9000 "MinIO      "
    check_port 9200 "ES         "
    check_port 8888 "IAM        "
    check_port 8989 "Model      "
    check_port 9898 "MCP        "
    check_port 8889 "Knowledge  "
    check_port 9988 "App        "
    check_port 9797 "Operate    "
    check_port 9990 "Channel    "
    check_port 8890 "Assistant  "
    check_port 8990 "Agent      "
    check_port 8088 "BFF(API)   "
    check_port 8080 "Frontend   "
    echo ""

    if command -v docker &>/dev/null; then
        echo "========== Docker Containers =========="
        docker compose ps 2>/dev/null || echo "  None"
        echo ""
    fi
}

# ==========================================
# Logs
# ==========================================
show_logs() {
    cd "$PROJECT_DIR"
    local svc="${1:-}"
    if [ -n "$svc" ] && [ -f "project/logs/${svc}.log" ]; then
        tail -f "project/logs/${svc}.log"
    elif [ -n "$svc" ]; then
        docker compose logs -f --tail=100 "$svc" 2>/dev/null || warn "No logs for: ${svc}"
    else
        docker compose logs -f --tail=100 2>/dev/null || warn "Usage: ./start.sh logs <service-name>"
    fi
}

# ==========================================
# Deploy
# ==========================================
do_deploy() {
    if ! command -v docker &>/dev/null; then
        err "Docker not installed"
    fi
    cd "$PROJECT_DIR"

    step "Pulling latest code..."
    git fetch origin 2>/dev/null || true
    git checkout custom 2>/dev/null || true
    git pull origin custom 2>/dev/null || warn "git pull failed, using local code"

    step "Building frontend image..."
    [ ! -f Dockerfile.frontend ] && cp Dockerfile.frontend.bak Dockerfile.frontend
    docker build -f Dockerfile.frontend -t wanwu-frontend:custom . || warn "Frontend build failed"

    step "Starting services..."
    start_docker
}

# ==========================================
# Help
# ==========================================
show_help() {
    echo "Wanwu Platform - Ubuntu Launcher"
    echo ""
    echo "Usage: ./start.sh [command]"
    echo ""
    echo "Commands:"
    echo "  (none)    Docker production mode"
    echo "  dev       Local dev mode (Go + frontend direct)"
    echo "  deploy    Deploy mode (pull + build + start)"
    echo "  frontend  Start frontend dev server only"
    echo "  stop      Stop all services"
    echo "  status    Show running status"
    echo "  logs <svc> View service logs"
    echo "  help      Show this help"
    echo ""
    echo "Examples:"
    echo "  ./start.sh                    # Docker mode"
    echo "  ./start.sh dev                # Local dev"
    echo "  ./start.sh logs bff-service   # View BFF logs"
}

# ==========================================
# Main
# ==========================================
case "${1:-default}" in
    dev)       start_dev ;;
    stop)      stop_all ;;
    status)    show_status ;;
    deploy)    do_deploy ;;
    frontend)  start_frontend ;;
    logs)      shift; show_logs "$@" ;;
    help|-h|--help) show_help ;;
    default)   start_docker ;;
    *)         show_help; exit 1 ;;
esac