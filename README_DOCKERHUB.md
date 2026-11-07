# MiCam Docker 镜像

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.html)
[![Architectures](https://img.shields.io/badge/Platforms-linux%2Famd64%20%7C%20linux%2Farm64-orange.svg)](#)

本镜像是开源项目 **[MiCam (AmigaMeow/micam)](https://github.com/AmigaMeow/micam)** 的 Docker 容器化打包版本。

> **MiCam 是什么？**  
> **MiCam** 是一款专为小米/米家摄像头打造的私有化监控桥接与本地 NVR 套件，支持局域网 P2P 低延迟直连、24小时本地原画连续录像、双摄分屏、云台控制与边缘 AI 分析。

> **关于 MiCam 的具体功能与特性**：  
> 本镜像仅作为 MiCam 的容器化部署方案。关于 MiCam 的详细功能介绍、使用场景、支持的摄像头型号及更新日志，请直接访问原项目主页查阅：  
> 👉 **[https://github.com/AmigaMeow/micam](https://github.com/AmigaMeow/micam)**

---

## 🚀 快速启动

### 方式 1：Docker Compose 启动（推荐）

```yaml
version: '3.8'

services:
  micam:
    image: micam:latest
    container_name: micam
    restart: unless-stopped
    # 推荐使用 host 网络模式，以保障局域网 P2P 直连与 UDP 通信性能
    network_mode: "host"
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

> **网络提示**：由于摄像头与本地服务通信依赖 PPCS 点对点连接和 UDP 54321 协议，**强烈推荐使用 `--net=host`（Host 模式）运行**。若必须使用 Bridge 网桥模式，请映射端口 `-p 8900:8900`。

---

## 🌐 访问与使用

1. 浏览器打开：`http://<宿主机IP>:8900`。
2. 使用 **米家 App 扫码** 授权绑定账号即可。
3. 容器首次启动会在后台自动向官方源拉取 `libmiot_camera_lite.so` 流媒体组件并保存在挂载目录，也可随时在 Web 界面系统设置中手动下载或上传。
4. 初始安全访问码位于 `./data/access-code.txt`，用于敏感操作验证。

---

## ⚙️ 环境变量与参数配置

| 环境变量 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `PORT` | `8900` | Web 界面与 API 监听端口 |
| `DATA_DIR` | `/data` | 持久化数据存放路径 |
| `CONFIG_PATH` | `/data/config.json` | 配置文件路径 |
| `AUTO_FETCH_MIOT_LIB` | `true` | 首次启动是否自动在后台拉取官方流媒体组件 |
| `TZ` | `Asia/Shanghai` | 容器运行时区 |

---

## 💾 持久化挂载目录说明

挂载宿主机目录至容器内 `/data`：
- `/data/config.json`：运行配置（录像策略、AI 开关、通知等）
- `/data/lib/`：存放 `libmiot_camera_lite.so` 官方组件（永久保留）
- `/data/recordings/`：本地录像切片文件
- `/data/models/`：本地 AI 模型
- `/data/access-code.txt`：安全访问码

---

## ⚖️ 开源协议与鸣谢

本项目完整继承上游原项目开源协议，采用 **[GNU Affero General Public License v3.0 (AGPL-3.0)](https://www.gnu.org/licenses/agpl-3.0.html)** 协议开源。

特别致谢本镜像所服务的上游开源项目：
- **[AmigaMeow/micam](https://github.com/AmigaMeow/micam)**：MiCam 智能家居监控套件原项目
- **[AlexxIT/go2rtc](https://github.com/AlexxIT/go2rtc)**：流媒体架构与纯 Go cs2 协议实现
- **[XiaoMi/xiaomi-miloco](https://github.com/XiaoMi/xiaomi-miloco)**：小米官方公开的边缘流媒体桥接组件
