ARG XRAY_IMAGE=ghcr.io/xtls/xray-core:26.9.9
FROM ${XRAY_IMAGE} AS xray

FROM python:3.12-alpine
COPY --from=xray /usr/local/bin/xray /usr/local/bin/xray
COPY exporter.py /app/exporter.py
USER nobody
CMD ["python3", "-u", "/app/exporter.py"]
