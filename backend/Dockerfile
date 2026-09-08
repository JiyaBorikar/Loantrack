# Stage 1: Build Python dependencies
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


# Stage 2: Runtime image
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app ./app

RUN useradd --create-home appuser && \
    chown -R appuser:appuser /app

ENV PATH="/opt/venv/bin:$PATH"

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]