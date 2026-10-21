FROM ghcr.io/astral-sh/uv:0.11.25@sha256:1e3808aa9023d0980e7c15b1fa7c1ac16ff35925780cf5c459858b2d693f01a9 AS uv
FROM python:3.12-slim-bookworm@sha256:5d9e6adc9abd558bc0ce05f9ab16cef71328916fc9728f6b81e337af86a737e2
COPY --from=uv /uv /usr/local/bin/uv
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_LINK_MODE=copy
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --extra cpu --no-install-project --no-cache
COPY src ./src
RUN uv sync --frozen --no-dev --extra cpu --no-cache \
    && groupadd --gid 10001 navcore \
    && useradd --uid 10001 --gid 10001 --no-create-home navcore
ENV PATH="/app/.venv/bin:$PATH" NAV_MODEL_DIR=/models NAV_LOG_LEVEL=INFO
USER 10001:10001
EXPOSE 8095
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8095/health/live',timeout=2)"
CMD ["python", "-m", "uvicorn", "navcore.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8095", "--workers", "1", "--ws-max-size", "1100000"]
