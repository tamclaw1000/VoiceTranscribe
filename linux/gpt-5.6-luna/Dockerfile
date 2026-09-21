FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VT_DATA_DIR=/data

WORKDIR /app
ARG INSTALL_ASR=true
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg openssl \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt requirements-asr.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "$INSTALL_ASR" = "true" ]; then pip install --no-cache-dir -r requirements-asr.txt; fi

COPY app ./app
COPY start.sh .
RUN chmod +x /app/start.sh && mkdir -p /data

EXPOSE 8000
CMD ["/app/start.sh"]
