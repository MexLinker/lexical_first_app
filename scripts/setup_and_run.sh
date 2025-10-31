#!/usr/bin/env bash
set -euo pipefail

# Lexical bootstrap script (macOS/Linux)
# - Installs dependencies on demand
# - Starts backend and/or Expo dev server
# - Performs health checks when possible
#
# Usage:
#   bash scripts/setup_and_run.sh [options]
#
# Key options:
#   --api <url>        Override API base URL exposed to Expo
#   --expo-port <port> Override Expo dev server port (default 8083)
#   --backend-port <p> Override backend port (default 3001)
#   --backend-wait <s> Health check timeout seconds (default 60)
#   --skip-install     Skip npm install steps
#   --install-only     Install dependencies then exit
#   --backend-only     Only run the backend (foreground)
#   --expo-only        Only run Expo (requires running backend)
#   --help             Show this message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

API_URL=""
EXPO_PORT=8083
BACKEND_PORT=3001
BACKEND_WAIT=60
SKIP_INSTALL=0
INSTALL_ONLY=0
START_BACKEND=1
START_EXPO=1

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_and_run.sh [options]

Options:
  --api <url>          Fully qualified API URL for the Expo app.
                       Defaults to http://localhost:<backend-port> when the
                       backend is started by this script, otherwise attempts
                       to detect your LAN IP.
  --expo-port <port>   Port for the Expo dev server (default: 8083).
  --backend-port <p>   Port for the Node backend (default: 3001).
  --backend-wait <s>   Seconds to wait for backend health (default: 60).
  --skip-install       Skip dependency installation.
  --install-only       Install dependencies and exit without starting servers.
  --backend-only       Start only the backend (foreground process).
  --expo-only          Start only the Expo dev server (assumes backend running).
  --help | -h          Show this help message and exit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api)
      API_URL="$2"; shift 2;;
    --expo-port)
      EXPO_PORT="$2"; shift 2;;
    --backend-port)
      BACKEND_PORT="$2"; shift 2;;
    --backend-wait)
      BACKEND_WAIT="$2"; shift 2;;
    --skip-install)
      SKIP_INSTALL=1; shift;;
    --install-only)
      INSTALL_ONLY=1; shift;;
    --backend-only)
      START_EXPO=0; shift;;
    --expo-only)
      START_BACKEND=0; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1;;
  esac
done

if [[ $START_BACKEND -eq 0 && $START_EXPO -eq 0 ]]; then
  echo "Nothing to do: both backend and Expo were disabled." >&2
  usage
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required. Please install Node.js 18+ and npm." >&2
    exit 1
  fi
}

require_cmd npm
if [[ $START_BACKEND -eq 1 ]]; then
  require_cmd node
fi
if [[ $START_EXPO -eq 1 ]]; then
  require_cmd npx
fi

HAS_CURL=1
if ! command -v curl >/dev/null 2>&1; then
  HAS_CURL=0
fi

detect_ip() {
  local ip=""
  if [[ "$(uname)" == "Darwin" ]]; then
    ip=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || ipconfig getifaddr en2 || echo "")
  else
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" && -x "/sbin/ip" ]]; then
      ip=$(/sbin/ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    elif [[ -z "$ip" ]]; then
      ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    fi
  fi
  echo "$ip"
}

if [[ -z "$API_URL" ]]; then
  if [[ $START_BACKEND -eq 1 ]]; then
    API_URL="http://localhost:${BACKEND_PORT}"
  else
    HOST_IP=$(detect_ip)
    if [[ -z "$HOST_IP" ]]; then
      echo "Could not detect host IP. Provide --api http://IP:PORT or set EXPO_PUBLIC_API_URL." >&2
      exit 1
    fi
    API_URL="http://${HOST_IP}:${BACKEND_PORT}"
  fi
fi

echo "Root directory: $ROOT_DIR"
echo "Backend port:   $BACKEND_PORT"
echo "Expo port:      $EXPO_PORT"
echo "API URL:        $API_URL"

echo
if [[ $SKIP_INSTALL -eq 0 ]]; then
  echo "Installing backend dependencies…"
  (cd "$ROOT_DIR/backend" && npm install)
  echo "Installing Expo app dependencies…"
  (cd "$ROOT_DIR/lexical-expo-app" && npm install)
else
  echo "Skipping dependency installation (per --skip-install)."
fi

echo
if [[ $INSTALL_ONLY -eq 1 ]]; then
  echo "Installation complete. Re-run without --install-only to start services."
  exit 0
fi

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo
    echo "Stopping backend (PID $BACKEND_PID)…"
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
  fi
}

BACKEND_PID=""

if [[ $START_BACKEND -eq 1 ]]; then
  if [[ $START_EXPO -eq 1 ]]; then
    echo "Starting backend in background…"
    BACKEND_LOG="$ROOT_DIR/backend.log"
    (cd "$ROOT_DIR/backend" && PORT="$BACKEND_PORT" node server.js >"$BACKEND_LOG" 2>&1 &)
    BACKEND_PID=$!
    trap cleanup EXIT

    if [[ $HAS_CURL -eq 1 ]]; then
      echo "Waiting for backend health at $API_URL/api/health (timeout ${BACKEND_WAIT}s)…"
      START_TIME=$(date +%s)
      while true; do
        if curl -fsS "$API_URL/api/health" >/dev/null 2>&1; then
          echo "Backend is healthy."
          break
        fi
        NOW=$(date +%s)
        ELAPSED=$((NOW - START_TIME))
        if [[ $ELAPSED -ge $BACKEND_WAIT ]]; then
          echo "Warning: health check did not succeed at $API_URL/api/health within ${BACKEND_WAIT}s (continuing)." >&2
          break
        fi
        sleep 1
      done
    else
      echo "curl not available; skipping backend health check." >&2
    fi
  else
    echo "Starting backend in foreground (Ctrl+C to stop)…"
    cd "$ROOT_DIR/backend"
    PORT="$BACKEND_PORT" exec node server.js
  fi
fi

if [[ $START_EXPO -eq 1 ]]; then
  echo "Starting Expo dev server…"
  cd "$ROOT_DIR/lexical-expo-app"
  EXPO_PUBLIC_API_URL="$API_URL" npx expo start --port "$EXPO_PORT"
fi
