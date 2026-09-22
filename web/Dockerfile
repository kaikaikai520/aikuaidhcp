FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY static ./static

# 数据目录（config.json 落盘位置）
ENV DATA_DIR=/data
VOLUME ["/data"]

EXPOSE 8000

# 端口通过环境变量 PORT 配置（默认 8000），host 网络模式下可自定义访问端口
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
