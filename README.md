# MiCam Docker

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![GitHub Actions Build](https://img.shields.io/badge/GitHub_Actions-Multi--arch_Build-brightgreen.svg)](.github/workflows/docker-publish.yml)
[![Docker Multi-Arch](https://img.shields.io/badge/Platforms-linux%2Famd64%20%7C%20linux%2Farm64-orange.svg)](#)

本项目是开源项目 **[MiCam (AmigaMeow/micam)](https://github.com/AmigaMeow/micam)** 的 Docker 镜像与运行套件。

> [!TIP]
> **关于 MiCam 的具体功能与特性**：  
> 本项目专注于提供 Docker 容器化运行支持。关于 MiCam 的功能介绍、设备支持列表与更新日志，请直接访问原项目主页：  
> 👉 **[https://github.com/AmigaMeow/micam](https://github.com/AmigaMeow/micam)**

---

## 🚀 使用方法

### 方式 1：Docker Compose 启动（推荐）

创建 `docker-compose.yml` 文件：

```yaml
services:
  micam:
    image: ghcr.io/libzonda/micam:latest  # 或使用 docker hub 镜像
    container_name: micam
    restart: unless-stopped
    
    # 推荐模式 A: Host 网络（与宿主机共享网络栈，P2P直连与UDP通信最稳定）
    network_mode: "host"
    
    # 模式 B: Bridge 网络（若使用 Bridge 模式，请注释 network_mode 并启用下行 ports）
    # ports:
    #   - "8900:8900"
    
    environment:
      - TZ=Asia/Shanghai
      - PORT=8900
      - AUTO_FETCH_MIOT_LIB=true
    volumes:
      - ./data:/data
    # 若需启用 Intel 核显 / VAAPI 硬件转码加速，请取消以下注释:
    # devices:
    #   - /dev/dri:/dev/dri
```

运行：
```bash
docker compose up -d
```

### 方式 2：Docker Run 命令行启动

```bash
docker run -d \
  --name micam \
  --restart unless-stopped \
  --net=host \
  -v $(pwd)/data:/data \
  --device /dev/dri:/dev/dri \
  micam:latest
```

---

## 🌐 访问与使用

1. 启动后在浏览器打开：`http://<宿主机IP>:8900`。
2. 打开米家 App 扫描网页上的二维码完成账号授权绑定。
3. 首次启动时，容器会在后台自动向官方源拉取 `libmiot_camera_lite.so` 流媒体组件并保存在 `./data/lib/` 目录；也可在 Web 界面系统设置中手动拉取或上传。
4. 初始安全访问码保存在 `./data/access-code.txt` 中，用于导出凭据等敏感操作验证。

---

## ⚙️ 环境变量与数据持久化

### 挂载目录说明
宿主机挂载至容器的 `./data` 目录持久化保存所有状态：
- `./data/config.json`：运行配置（录像策略、AI 开关、通知设置等）
- `./data/lib/`：官方流媒体组件（自动保存，容器重建不丢失）
- `./data/recordings/`：本地录像切片文件
- `./data/models/`：AI 模型文件
- `./data/access-code.txt`：敏感接口安全访问码

### 常用环境变量

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `PORT` | `8900` | 服务监听端口 |
| `TZ` | `Asia/Shanghai` | 容器运行时区 |
| `AUTO_FETCH_MIOT_LIB` | `true` | 是否在首次启动时自动在后台拉取官方流媒体组件 |

---

## 🛠️ 自行构建镜像（可选）

- **本地打包**：直接运行 `./build-docker.sh --pull --restart`（自动拉取上游最新 Tag 并一键重启容器）。
- **云端自动打包**：仓库内置 GitHub Actions 流水线，每日定时自动检测上游最新 Tag 并完成多架构镜像打包；也可在 GitHub 网页一键手动触发（默认自动拉取最新 Tag）。镜像将同时发布到 GHCR 与 Docker Hub。

---

## ⚖️ 开源许可证与鸣谢

本项目完整继承原项目的开源协议，基于 **[GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE)** 协议开源。

特别鸣谢以下来源开源项目：
- **[AmigaMeow/micam](https://github.com/AmigaMeow/micam)**：MiCam 智能家居监控套件原项目
- **[AlexxIT/go2rtc](https://github.com/AlexxIT/go2rtc)**：流媒体架构与纯 Go cs2 协议实现
- **[XiaoMi/xiaomi-miloco](https://github.com/XiaoMi/xiaomi-miloco)**：小米官方公开的边缘流媒体桥接组件
