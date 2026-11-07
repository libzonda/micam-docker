#!/usr/bin/env bash
# ==============================================================================
# MiCam Docker 自动化构建与打包脚本
# 支持当前版本打包与后续持续更新构建
# ==============================================================================

set -euo pipefail

# 颜色高亮
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 脚本根目录
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MICAM_DIR="${ROOT_DIR}/micam"
REPO_URL="https://github.com/AmigaMeow/micam.git"

# 默认构建配置
PULL_UPDATE=false
WITH_AI=false
PREFETCH_LIB=false
NO_CACHE=false
RUN_TEST=false
RESTART_CONTAINER=false
CUSTOM_TAG=""
IMAGE_NAME="micam"

print_help() {
    cat << EOF
${BOLD}MiCam Docker 自动化打包工具${NC}

${BOLD}用法:${NC}
  ./build-docker.sh [选项]

${BOLD}选项:${NC}
  -u, --pull, --update    构建前拉取 micam 代码库的最新更新 (git pull)
  -r, --restart           构建完成后自动重启当前正在运行的 micam 容器
  -t, --tag <tag>         指定自定义 Docker 镜像标签 (默认: micam:<版本号> 及 micam:latest)
  --with-ai               构建包含本地 ONNX AI 模型推理依赖 (numpy, opencv, onnxruntime)
  --fetch-lib             构建时直接预下载官方 libmiot_camera_lite.so 打入镜像
  --no-cache              Docker 构建时不使用缓存
  --run                   镜像构建成功后自动启动一个测试容器
  -h, --help              显示本帮助信息

${BOLD}使用示例:${NC}
  ./build-docker.sh                       # 直接基于当前 micam 项目构建
  ./build-docker.sh --pull                # 检查并拉取最新项目代码，然后重新打包
  ./build-docker.sh --pull --restart      # 自动更新代码、构建镜像并一键重启容器
  ./build-docker.sh --pull --with-ai      # 拉取最新代码，并构建带本地 AI 推理功能的镜像
  ./build-docker.sh -t mycamera:v1.0      # 指定自定义镜像 Tag
EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--pull|--update)
            PULL_UPDATE=true
            shift
            ;;
        -r|--restart)
            RESTART_CONTAINER=true
            shift
            ;;
        -t|--tag)
            CUSTOM_TAG="$2"
            shift 2
            ;;
        --with-ai)
            WITH_AI=true
            shift
            ;;
        --fetch-lib)
            PREFETCH_LIB=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --run)
            RUN_TEST=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}[错误] 未知参数: $1${NC}" >&2
            print_help
            exit 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${CYAN}${BOLD}       MiCam Docker 自动化构建系统                  ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}"

# 1. 检查 Docker 环境
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[错误] 未找到 docker 命令，请先安装 Docker。${NC}" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[错误] Docker 守护进程未运行，或者当前用户没有运行 docker 的权限。${NC}" >&2
    exit 1
fi

# 2. 检查或更新 micam 仓库
if [ ! -d "${MICAM_DIR}" ]; then
    echo -e "${YELLOW}[!] 未在当前目录下检测到 micam 源码目录，正在克隆官方仓库...${NC}"
    git clone "${REPO_URL}" "${MICAM_DIR}"
fi

if [ "${PULL_UPDATE}" = true ]; then
    echo -e "${BLUE}[*] 正在检查上游最新发布 Tag...${NC}"
    UPSTREAM_LATEST=$(git ls-remote --tags --refs "${REPO_URL}" | awk -F'/' '{print $3}' | sort -V | tail -n 1 || true)
    pushd "${MICAM_DIR}" > /dev/null
    git fetch --tags origin
    if [ -n "${UPSTREAM_LATEST}" ]; then
        echo -e "${GREEN}[+] 检出上游最新 Tag: ${UPSTREAM_LATEST}${NC}"
        git checkout "${UPSTREAM_LATEST}" 2>/dev/null || git pull origin master
    else
        CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")"
        git pull origin "${CURRENT_BRANCH}"
    fi
    popd > /dev/null
fi

# 3. 提取项目版本号与 Git Commit
VERSION=""
if [ -f "${MICAM_DIR}/platform/fnos/manifest" ]; then
    VERSION="$(grep -E '^version' "${MICAM_DIR}/platform/fnos/manifest" | cut -d= -f2 | tr -d ' ' || true)"
fi

if [ -z "${VERSION}" ] && [ -d "${MICAM_DIR}/.git" ]; then
    VERSION="$(cd "${MICAM_DIR}" && git describe --tags --always 2>/dev/null || true)"
fi

if [ -z "${VERSION}" ]; then
    VERSION="latest"
fi

GIT_COMMIT=""
if [ -d "${MICAM_DIR}/.git" ]; then
    GIT_COMMIT="$(cd "${MICAM_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)"
fi

echo -e "[*] 项目版本: ${GREEN}${BOLD}${VERSION}${NC} (Commit: ${GIT_COMMIT:-none})"
echo -e "[*] 本地 AI 推理支持: $([ "${WITH_AI}" = true ] && echo -e "${GREEN}启用${NC}" || echo -e "${YELLOW}禁用 (轻量模式)${NC}")"
echo -e "[*] 构建时预下载流媒体组件: $([ "${PREFETCH_LIB}" = true ] && echo -e "${GREEN}是${NC}" || echo -e "${YELLOW}否 (容器启动时按需下载)${NC}")"

# 4. 构建参数准备
TAGS=()
if [ -n "${CUSTOM_TAG}" ]; then
    TAGS+=("-t" "${CUSTOM_TAG}")
else
    TAGS+=("-t" "${IMAGE_NAME}:${VERSION}")
    TAGS+=("-t" "${IMAGE_NAME}:latest")
fi

BUILD_ARGS=()
BUILD_ARGS+=("--build-arg" "APP_VERSION=${VERSION}")
BUILD_ARGS+=("--build-arg" "WITH_AI=${WITH_AI}")
BUILD_ARGS+=("--build-arg" "PREFETCH_LIB=${PREFETCH_LIB}")

DOCKER_FLAGS=()
if [ "${NO_CACHE}" = true ]; then
    DOCKER_FLAGS+=("--no-cache")
fi

echo -e "\n${BLUE}[*] 开始执行 Docker 多阶段构建...${NC}"
START_TIME=$(date +%s)

docker build \
    -f "${ROOT_DIR}/Dockerfile" \
    "${BUILD_ARGS[@]}" \
    "${DOCKER_FLAGS[@]}" \
    "${TAGS[@]}" \
    "${ROOT_DIR}"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "\n${GREEN}${BOLD}🎉 Docker 镜像构建完成！(耗时: ${DURATION} 秒)${NC}"

# 5. 显示构建出的镜像信息
echo -e "\n${BOLD}构建产物信息:${NC}"
docker images | grep -E "REPOSITORY|${IMAGE_NAME}" | head -n 5

# 6. 运行指引提示
echo -e "\n${CYAN}${BOLD}====================================================${NC}"
echo -e "${CYAN}${BOLD}                  快速运行指引                      ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${BOLD}方式 1: 使用 docker run 命令启动${NC}"
echo -e "  docker run -d \\"
echo -e "    --name micam \\"
echo -e "    --restart unless-stopped \\"
echo -e "    -p 8900:8900 \\"
echo -e "    -v \$(pwd)/data:/data \\"
echo -e "    --device /dev/dri:/dev/dri \\  # (可选: 开启 Intel 核显/VAAPI 硬件加速)"
echo -e "    ${IMAGE_NAME}:${VERSION}"
echo
echo -e "${BOLD}方式 2: 使用 docker compose 启动${NC}"
echo -e "  docker compose up -d"
echo
echo -e "${BOLD}Web 管理界面地址:${NC}"
echo -e "  http://<主机IP>:8900"
echo

if [ "${RUN_TEST}" = true ]; then
    echo -e "${BLUE}[*] 正在启动测试容器 micam-test...${NC}"
    docker rm -f micam-test 2>/dev/null || true
    docker run -d \
        --name micam-test \
        --net=host \
        -v "${ROOT_DIR}/data:/data" \
        "${IMAGE_NAME}:${VERSION}"
    echo -e "${GREEN}[+] 测试容器已启动，请访问 http://localhost:8900 验证。${NC}"
fi

if [ "${RESTART_CONTAINER}" = true ]; then
    echo -e "${BLUE}[*] 正在平滑更新重启运行中的 micam 容器...${NC}"
    if docker compose ps --services 2>/dev/null | grep -q "micam"; then
        docker compose up -d --force-recreate
        echo -e "${GREEN}[+] 已通过 docker compose 成功重载最新容器！${NC}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^micam$"; then
        docker stop micam 2>/dev/null || true
        docker rm micam 2>/dev/null || true
        DRI_ARG=""
        if [ -e /dev/dri ]; then
            DRI_ARG="--device /dev/dri:/dev/dri"
        fi
        docker run -d \
            --name micam \
            --restart unless-stopped \
            --net=host \
            -v "${ROOT_DIR}/data:/data" \
            ${DRI_ARG} \
            "${IMAGE_NAME}:${VERSION}"
        echo -e "${GREEN}[+] 已成功重启运行最新 micam 容器！${NC}"
    else
        echo -e "${YELLOW}[!] 未发现运行中的 micam 容器，正在通过 docker compose 启动...${NC}"
        docker compose up -d
        echo -e "${GREEN}[+] micam 容器已启动！${NC}"
    fi
fi

