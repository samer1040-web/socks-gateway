FROM python:3.12-slim-bookworm

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HOST=0.0.0.0 \
    PORT=1080 \
    UDP_ASSOCIATE=0 \
    MAX_CONNS=100 \
    MAX_PER_IP=100 \
    UDPGW_TASKS=16

RUN apt-get update \
    && apt-get install -y --no-install-recommends tor curl ca-certificates jq util-linux \
    && rm -rf /var/lib/apt/lists/*

# WARP: wgcf (تسجيل حساب مجاني) + wireproxy (WireGuard -> SOCKS5 محلي).
# فشل التنزيل هنا لا يفشل البناء؛ السكربت يتجاوز WARP تلقائيًا إن لم يجد الملفين.
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) A=amd64 ;; \
        arm64) A=arm64 ;; \
        *) echo "[build] unsupported arch, WARP skipped"; exit 0 ;; \
    esac; \
    ( \
      url="$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest \
            | jq -r --arg a "linux_${A}" '.assets[] | select(.name | endswith($a)) | .browser_download_url' \
            | head -n1)"; \
      test -n "$url"; \
      curl -fsSL "$url" -o /usr/local/bin/wgcf; \
      chmod +x /usr/local/bin/wgcf; \
      curl -fsSL "https://github.com/pufferffish/wireproxy/releases/latest/download/wireproxy_linux_${A}.tar.gz" \
        | tar -xz -C /usr/local/bin wireproxy; \
      chmod +x /usr/local/bin/wireproxy; \
    ) || { echo "[build] WARP download failed, skipping"; rm -f /usr/local/bin/wgcf /usr/local/bin/wireproxy; }

WORKDIR /app
COPY socks_gateway.py entrypoint.sh /app/
COPY torrc.conf /etc/tor/torrc
RUN sed -i 's/\r$//' /app/entrypoint.sh /etc/tor/torrc \
    && chmod +x /app/entrypoint.sh \
    && mkdir -p /data

# المنفذ الذي تضبطه في Railway TCP Proxy (يجب أن يطابق PORT)
EXPOSE 1080

ENTRYPOINT ["/app/entrypoint.sh"]