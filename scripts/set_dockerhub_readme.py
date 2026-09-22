#!/usr/bin/env python3
"""设置 Docker Hub 仓库（dehua/aikuaidhcp）的描述与 README。

用法（任选一种提供 token）:
  1. 环境变量:  set DOCKERHUB_TOKEN=你的token   （Windows cmd）
                export DOCKERHUB_TOKEN=你的token （bash）
  2. 交互输入:  直接运行脚本，按提示粘贴 token

运行:
  python scripts/set_dockerhub_readme.py

脚本会读取项目根目录 README.md 作为 Docker Hub 的 README（full_description，
支持 Markdown 渲染），并设置一行简短描述（description）。
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

USERNAME = "dehua"
REPO = "aikuaidhcp"

# 简短描述，Docker Hub 限制 100 字符
DESCRIPTION = "爱快 DHCP 网关切换助手：内网 Web 服务，浏览器一键切换终端 DHCP 网关 A/B"


def read_readme() -> str:
    # 脚本位于 scripts/ 下，README 在项目根目录（上一级）
    here = os.path.dirname(os.path.abspath(__file__))
    readme = os.path.join(here, "..", "README.md")
    if os.path.exists(readme):
        with open(readme, encoding="utf-8") as f:
            return f.read()
    return ""


def main() -> None:
    token = os.environ.get("DOCKERHUB_TOKEN")
    if not token:
        token = input("请输入 Docker Hub Access Token: ").strip()
    if not token:
        print("未提供 token，退出。")
        sys.exit(1)

    readme = read_readme()
    if not readme:
        print("未找到项目 README.md，仅更新 description。")

    payload = {
        "description": DESCRIPTION,
        "full_description": readme,
    }

    auth = base64.b64encode(f"{USERNAME}:{token}".encode()).decode()
    req = urllib.request.Request(
        f"https://hub.docker.com/v2/repositories/{USERNAME}/{REPO}/",
        data=json.dumps(payload).encode("utf-8"),
        method="PATCH",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Basic {auth}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"成功 HTTP {resp.status}")
            print(resp.read().decode("utf-8", errors="ignore"))
    except urllib.error.HTTPError as e:
        print(f"失败 HTTP {e.code}")
        print(e.read().decode("utf-8", errors="ignore"))


if __name__ == "__main__":
    main()
