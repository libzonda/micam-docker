# syntax=docker/dockerfile:1
# ==========================================
# Stage 1: Build Frontend & Go Binary
# ==========================================
FROM golang:latest AS builder

ARG APP_VERSION="0.41.40"
ARG TARGETARCH
ARG GOPROXY="https://goproxy.cn,direct"

ENV GOTOOLCHAIN=auto

# 安装 Node.js 用于执行 assemble-web.js 组装单文件前端
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 优先下载 Go 依赖以利用构建缓存
COPY micam/go.mod micam/go.sum ./
RUN go env -w GOPROXY="${GOPROXY}" && go mod download

# 复制项目代码
COPY micam/ .

# 1. 组装前端 index.html
RUN node build/assemble-web.js

# 2. 编译 Go 服务 micamd
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build \
    -trimpath \
    -ldflags="-s -w -X main.appVersion=${APP_VERSION}" \
    -o /out/app/micamd \
    ./cmd/micamd

# 3. 组织运行时 app 目录
RUN mkdir -p /out/app/www /out/app/ui /out/app/ai /out/app/miot /out/app/scripts \
    && cp -r platform/fnos/app/www/* /out/app/www/ \
    && cp -r platform/fnos/app/ui/* /out/app/ui/ \
    && cp platform/fnos/app/shell.html /out/app/shell.html \
    && cp -r platform/fnos/app/ai/* /out/app/ai/ \
    && cp app/miot/*.py /out/app/miot/ \
    && cp scripts/fetch-miot-lib.sh /out/app/scripts/fetch-miot-lib.sh \
    && chmod +x /out/app/scripts/*.sh /out/app/micamd

# ==========================================
# Stage 2: Runtime Environment
# ==========================================
FROM python:3.11-slim-bookworm AS runner

LABEL maintainer="AmigaMeow & MiCam Docker Team" \
      description="Docker image for MiCam - Xiaomi Smart Camera Management & NVR"

ARG WITH_AI=false
ARG PREFETCH_LIB=false
ARG TARGETARCH
ARG PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TRIM_APPDEST=/app \
    MICAM_DATA_DIR=/data \
    MICAM_CONFIG=/data/config.json \
    PORT=8900

# 安装基础运行时工具、ffmpeg、VAAPI驱动加速库与tini
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    tzdata \
    tini \
    procps \
    mesa-va-drivers \
    vainfo \
    && (apt-get install -y --no-install-recommends intel-media-va-driver-non-free 2>/dev/null \
        || apt-get install -y --no-install-recommends intel-media-va-driver 2>/dev/null \
        || true) \
    && rm -rf /var/lib/apt/lists/*

# 安装核心 Python 依赖 (miio 通信必须)
RUN if [ -n "${PIP_INDEX_URL}" ]; then \
        pip config set global.index-url "${PIP_INDEX_URL}"; \
    fi \
    && pip install --no-cache-dir cryptography

# 可选安装本地 ONNX AI 推理依赖 (若开启 WITH_AI=true)
RUN if [ "$WITH_AI" = "true" ]; then \
        pip install --no-cache-dir numpy opencv-python-headless onnxruntime; \
    fi

WORKDIR /app

# 从 builder 复制应用资产
COPY --from=builder /out/app /app
COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 若构建时指定 PREFETCH_LIB=true，则预先下载好官方流媒体组件至 /app/lib
RUN if [ "$PREFETCH_LIB" = "true" ]; then \
        mkdir -p /app/lib && bash /app/scripts/fetch-miot-lib.sh /app/lib || true; \
    fi

VOLUME ["/data"]
EXPOSE 8900

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:${PORT:-8900}/api/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["micamd"]

