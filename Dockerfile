# Production image: runtime dependencies only (no pytest/ruff), non-root user.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /service

# requirements.txt only - requirements-dev.txt is never copied into the image.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
 && useradd --system --no-create-home --uid 10001 --shell /usr/sbin/nologin appuser

# Code stays owned by root, so the app user cannot modify it at runtime.
COPY app ./app

USER 10001
EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2).status == 200 else 1)"

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--graceful-timeout", "10", "app.main:app"]
