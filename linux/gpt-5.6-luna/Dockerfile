FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VT_DATA_DIR=/data

WORKDIR /app
ARG INSTALL_ASR=false
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt requirements-asr.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "$INSTALL_ASR" = "true" ]; then pip install --no-cache-dir -r requirements-asr.txt; fi

COPY app ./app
RUN mkdir -p /data

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
