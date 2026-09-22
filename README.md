# 爱快 DHCP 网关切换助手（aikuaidhcp）

一款自用工具：在内网部署一个 Web 服务，浏览器访问即可查看爱快（iKuai）路由器里
DHCP 静态分配的终端列表，并对每台终端在**预设的两个网关（A/B）之间一键切换**。

## 当前形态

- **Web 服务**（`web/`）：Python + FastAPI，Docker 部署，浏览器输入 `http://内网IP:8000` 即可使用。

## 快速开始

```bash
cd web
docker compose up -d --build
```

浏览器访问 `http://<内网IP>:8000`，首次打开配置爱快连接信息 + 网关 A/B 即可。

本地直接运行：

```bash
cd web
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## 文档

- 产品设计：`docs/PRD.md`
- 技术方案：`docs/TECH_DESIGN.md`
- Web 服务说明：`web/README.md`

## 前置条件

- 需要爱快 Web 管理账号（默认 `admin`）。
- 需要先在爱快「网络设置 → DHCP设置 → DHCP静态分配」中为终端建立静态绑定记录。
- 爱快需支持「静态分配指定网关」（免费版 3.7.x 实测支持）。
