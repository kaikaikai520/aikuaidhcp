# NAS 部署：docker-compose.yml 编写说明

本项目的 Web 服务用 Docker 部署，只需一个 `docker-compose.yml` 文件即可在NAS 上拉起。
下面是这个 yml 文件的逐字段讲解，重点说明**哪些文件夹要映射**和**端口填多少**。

---

## 一、完整示例文件

**免构建版（推荐，直接拉 Docker Hub 预构建镜像）**：

```yaml
services:
  aikuaidhcp:
    image: dehua/aikuaidhcp:latest        # 镜像地址（拉预构建，无需本地 build）
    container_name: aikuaidhcp            # 容器名，可自定义
    ports:
      - "8000:8000"                       # 端口映射：宿主机:容器
    volumes:
      - ./data:/data                      # 数据目录映射：宿主机:容器
    restart: unless-stopped               # 开机自启 / 异常自动重启
```

**本地构建版（在 NAS 上 build，需要先把代码上传到 NAS）**：

```yaml
services:
  aikuaidhcp:
    build: .                              # 用当前目录的 Dockerfile 构建
    container_name: aikuaidhcp
    ports:
      - "8000:8000"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

---

## 二、需要映射的文件夹（volumes）

**只有 1 个文件夹需要映射：`/data`**。

| 宿主机路径 | 容器内路径 | 作用 |
|-----------|-----------|------|
| `./data`（或任意你选的位置） | `/data` | 存放服务运行时数据 |

这个目录里会生成两个文件，**必须持久化**，否则容器重建后配置丢失：

| 文件 | 内容 |
|------|------|
| `config.json` | 爱快连接信息（IP/端口/账号/密码）+ 网关 A/B 预设 |
| `hidden.json` | 你隐藏的终端 mac 列表 |

> **注意**：代码本身（`app/`、`static/` 等）**不需要映射**——它们已经打包进镜像里了。
> 映射 `/data` 的唯一目的，就是让「配置」和「隐藏列表」这两份数据在容器重建后不丢。

**宿主机路径写法**（两种都可以）：

```yaml
volumes:
  - ./data:/data                          # 相对路径：compose 文件所在目录下的 data 文件夹
  # 或
  - /vol1/docker/aikuaidhcp/data:/data    # 绝对路径：共享文件夹的完整路径（更稳妥）
```

> NAS 上建议用**绝对路径**，避免因 compose 文件位置变动导致数据卷找不到。

---

## 三、端口填多少（ports）

格式永远是 `"宿主机端口:容器端口"`，**冒号右边固定 8000，左边随便填**。

```yaml
ports:
  - "8000:8000"    # 默认：访问 http://NAS内网IP:8000
  # 若 8000 被占用，改成左侧即可：
  # - "8080:8000"  # 访问 http://NAS内网IP:8080
  # - "8888:8000"  # 访问 http://NAS内网IP:8888
```

| 项 | 值 | 说明 |
|----|----|------|
| 冒号**右边**（容器内端口） | `8000` | **固定不变**，程序监听的就是 8000 |
| 冒号**左边**（宿主机端口） | 任意 | 你最终在浏览器访问的端口 |

**判断端口是否被占用**：如果浏览器访问没反应，多半是左侧端口被别的服务占了，改个数字即可（如 `8080:8000`）。

---

## 四、逐字段说明速查

| 字段 | 必填 | 含义 |
|------|------|------|
| `image` / `build` | 二选一 | 拉取预构建镜像 / 本地构建 |
| `container_name` | 否 | 容器显示名，方便 `docker ps` 辨认 |
| `ports` | 是 | 端口映射，格式 `"宿主机:容器"` |
| `volumes` | 是 | 数据目录映射，只有 `/data` 需要 |
| `restart` | 否 | `unless-stopped` = 开机自启 + 异常自动拉起 |

---

## 五、部署步骤（NAS）

1. 把上面的 yml 内容保存为 `docker-compose.yml`，放到 NAS 某目录（如 `/vol1/docker/aikuaidhcp/`）。
2. 在该目录执行：

   ```bash
   docker compose up -d
   ```

   或打开「Docker 应用 → Compose → 新建项目」，粘贴 yml 内容直接应用。
3. 浏览器访问 `http://<NAS内网IP>:8000`（若改了左侧端口则用对应端口）。

---

## 六、更新与卸载

```bash
# 更新到最新镜像
docker compose pull && docker compose up -d

# 查看日志
docker compose logs -f

# 停止并删除容器（数据卷 ./data 会保留）
docker compose down
```
