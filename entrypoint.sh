#!/usr/bin/env bash
set -u

WARP_PORT="${WARP_PORT:-40000}"
TOR_PORT=9050
ENABLE_WARP="${ENABLE_WARP:-1}"
ENABLE_TOR="${ENABLE_TOR:-1}"
ENABLE_DIRECT="${ENABLE_DIRECT:-1}"
WARP_DIR="${WARP_DIR:-/data/warp}"
PROXY_FILE=/app/proxies.txt

NOBODY=(setpriv --reuid=65534 --regid=65534 --clear-groups)
CLEAN=(env -u SOCKS_USER -u SOCKS_PASS -u SOCKS_PASS_FILE)

supervise() {
  local name=$1
  shift
  (
    while true; do
      "$@" >"/tmp/${name}.log" 2>&1
      echo "[${name}] exited; restarting in 5s"
      sleep 5
    done
  ) &
}

wait_port() {
  local port=$1 tries=${2:-20} i
  for ((i = 0; i < tries; i++)); do
    if (echo >"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

setup_warp() {
  [ "$ENABLE_WARP" = "1" ] || return 1
  if ! command -v wgcf >/dev/null || ! command -v wireproxy >/dev/null; then
    echo "[warp] binaries not installed, skipping"
    return 1
  fi
  mkdir -p "$WARP_DIR" || return 1

  if [ ! -s "$WARP_DIR/wgcf-profile.conf" ]; then
    local i
    for i in 1 2 3 4 5; do
      if (
        cd "$WARP_DIR" &&
          { [ -s wgcf-account.toml ] || wgcf register --accept-tos >/dev/null 2>&1; } &&
          wgcf generate >/dev/null 2>&1
      ) && [ -s "$WARP_DIR/wgcf-profile.conf" ]; then
        break
      fi
      echo "[warp] registration attempt ${i} failed"
      sleep $((i * 3))
    done
  fi
  [ -s "$WARP_DIR/wgcf-profile.conf" ] || { echo "[warp] no profile, skipping"; return 1; }

  mkdir -p /run/wireproxy
  cat >/run/wireproxy/wireproxy.conf <<EOF
WGConfig = ${WARP_DIR}/wgcf-profile.conf

[Socks5]
BindAddress = 127.0.0.1:${WARP_PORT}
EOF
  chown -R 65534:65534 "$WARP_DIR" /run/wireproxy
  chmod 700 "$WARP_DIR"

  supervise wireproxy "${CLEAN[@]}" "${NOBODY[@]}" wireproxy -c /run/wireproxy/wireproxy.conf
  if wait_port "$WARP_PORT" 15; then
    local trace
    trace="$(curl -s --max-time 15 --socks5-hostname "127.0.0.1:${WARP_PORT}" \
      https://www.cloudflare.com/cdn-cgi/trace | grep '^warp=' || true)"
    echo "[warp] up (${trace:-unverified})"
    return 0
  fi
  echo "[warp] port not open, skipping"
  return 1
}

setup_tor() {
  [ "$ENABLE_TOR" = "1" ] || return 1
  command -v tor >/dev/null || { echo "[tor] not installed, skipping"; return 1; }
  supervise tor "${CLEAN[@]}" tor -f /etc/tor/torrc
  echo "[tor] starting on 127.0.0.1:${TOR_PORT} (fallback tier)"
  return 0
}

WARP_OK=0
TOR_OK=0
setup_warp && WARP_OK=1
setup_tor && TOR_OK=1

{
  [ "$ENABLE_DIRECT" = "1" ] && echo "direct tier=3"
  [ "$WARP_OK" = "1" ] && echo "socks5://127.0.0.1:${WARP_PORT} tier=1"
  [ "$TOR_OK" = "1" ] && echo "socks5://127.0.0.1:${TOR_PORT} tier=2"
  if [ -n "${EXTRA_PROXIES:-}" ]; then
    printf '%s\n' "$EXTRA_PROXIES" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e '/^$/d'
  fi
} >"$PROXY_FILE"
[ -s "$PROXY_FILE" ] || echo "direct tier=3" >"$PROXY_FILE"
chown 65534:65534 "$PROXY_FILE"
chmod 600 "$PROXY_FILE"
echo "[entry] $(wc -l <"$PROXY_FILE") upstream(s) configured"

exec "${NOBODY[@]}" python3 /app/socks_gateway.py --proxies "$PROXY_FILE" "$@"