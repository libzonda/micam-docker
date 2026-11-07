#!/bin/bash
set -e

# ==========================================
# MiCam Docker 入口点脚本
# ==========================================

PORT="${PORT:-8900}"
DATA_DIR="${DATA_DIR:-/data}"
CONFIG_PATH="${CONFIG_PATH:-$DATA_DIR/config.json}"
AUTO_FETCH_MIOT_LIB="${AUTO_FETCH_MIOT_LIB:-true}"
FFMPEG_PATH="${FFMPEG_PATH:-/usr/bin/ffmpeg}"

# 1. 如果用户执行的是版本查询或交互式 shell 命令，直接放行
if [ "$#" -gt 0 ]; then
    if [ "$1" = "micamd" ] && [ "$2" = "--version" -o "$2" = "-version" ]; then
        exec /app/micamd "$2"
    fi
    if [ "$1" = "--version" -o "$1" = "-version" ]; then
        exec /app/micamd "$1"
    fi
    if [ "$1" != "micamd" ] && [[ "$1" != -* ]]; then
        exec "$@"
    fi
fi

echo "============================================="
echo "   MiCam 智能家居监控套件 (Docker 容器版)   "
echo "============================================="
echo "[*] 服务端口: $PORT"
echo "[*] 数据目录: $DATA_DIR"
echo "[*] 配置文件: $CONFIG_PATH"
echo "[*] FFmpeg路径: $FFMPEG_PATH"

# 2. 确保数据目录及子目录就绪
mkdir -p "$DATA_DIR/lib" \
         "$DATA_DIR/recordings" \
         "$DATA_DIR/models" \
         "$DATA_DIR/events" \
         "$DATA_DIR/web"

# 3. 检查与处理官方流媒体闭源组件 libmiot_camera_lite.so
TARGET_SO="$DATA_DIR/lib/libmiot_camera_lite.so"
APP_SO="/app/lib/libmiot_camera_lite.so"

if [ -f "$TARGET_SO" ]; then
    export MICAM_MIOT_LIB="$TARGET_SO"
    echo "[+] 检测到持久化流媒体组件已就绪: $TARGET_SO"
elif [ -f "$APP_SO" ]; then
    export MICAM_MIOT_LIB="$APP_SO"
    echo "[+] 检测到镜像内置流媒体组件已就绪: $APP_SO"
else
    export MICAM_MIOT_LIB="$TARGET_SO"
    if [ "$AUTO_FETCH_MIOT_LIB" = "true" ]; then
        echo "[*] 未检测到 libmiot_camera_lite.so，已启动后台异步拉取..."
        (
            if bash /app/scripts/fetch-miot-lib.sh "$DATA_DIR/lib" >/dev/null 2>&1; then
                echo "[+] [后台任务] 官方流媒体组件自动拉取完成！已激活实时视频流能力。"
            else
                echo "[!] [后台任务] 官方组件后台拉取未完成（可随时在 Web 界面系统设置中点击手动拉取）。"
            fi
        ) &
    else
        echo "[i] 已跳过自动拉取流媒体组件 (AUTO_FETCH_MIOT_LIB=false)"
        echo "    可在 Web 界面系统设置中手动点击拉取，或将 .so 放入 data/lib/ 目录。"
    fi
fi

# 4. 启动 micamd 服务
echo "[*] 正在启动 MiCam 服务进程..."
EXTRA_ARGS=()
for arg in "$@"; do
    if [ "$arg" != "micamd" ]; then
        EXTRA_ARGS+=("$arg")
    fi
done

exec /app/micamd \
    --http ":$PORT" \
    --appdest "/app" \
    --data "$DATA_DIR" \
    --config "$CONFIG_PATH" \
    --ffmpeg "$FFMPEG_PATH" \
    "${EXTRA_ARGS[@]}"
