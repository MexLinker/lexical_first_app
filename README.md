# Lexical Expo App + MySQL Backend

This project delivers a minimal end-to-end vocabulary lookup experience: an Expo React Native client fetches definitions from a Node.js + Express API that in turn queries a MySQL database. The repository contains both the mobile/web client and the backend so you can bootstrap the whole stack locally with a single command.

---

## Repository Layout

- `lexical-expo-app/`
  - Expo (React Native + web) application created with `create-expo-app`.
  - `app/index.tsx` renders the search UI.
  - `constants/backend.ts` resolves the backend base URL from `EXPO_PUBLIC_API_URL` or the Expo host IP.
- `backend/`
  - Express server defined in `server.js` with MySQL connectivity via `mysql2/promise`.
  - `.env` (ignored by git) holds local database credentials.
  - `.env.example` should be copied into `.env` and populated before running.
- `scripts/`
  - Cross-platform automation helpers for installing dependencies and launching both services together (`setup_and_run.sh` and `setup_and_run.ps1`).
- `docs/`
  - Architectural notes and longer-term plans (`TECHNICAL_ROADMAP.md`).

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Node.js | 18.x or newer | Required for both backend and Expo.
| npm | 9.x or newer | Bundled with Node.js; used for installs.
| MySQL | 8.x (remote or local) | Provide credentials via `backend/.env`.
| Expo Go (Android/iOS) | Latest | Optional, for testing on devices.
| PowerShell 5+ / Bash | Platform-specific | Required for the automation scripts.

> **Database access**: Update `backend/.env` with valid MySQL host, port, username, password, and database before starting the backend.

---

## Quick Start (Recommended)

### 1. Prepare environment variables

```bash
cd backend
cp .env.example .env
# edit .env with your DB credentials
```

### 2. Run the combined setup script

**macOS/Linux:**
```bash
bash scripts/setup_and_run.sh
```

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_and_run.ps1
```

What the script does:
1. Installs `backend` and `lexical-expo-app` dependencies (skip with `--skip-install` / `-SkipInstall`).
2. Starts the backend on port `3001` by default and waits for `/api/health`.
3. Launches the Expo dev server on port `8083`, injecting `EXPO_PUBLIC_API_URL` so the app talks to the backend.

Once Expo starts, open the Web UI at `http://localhost:8083`, or scan the QR code in Expo Go to test on a device.

---

## Automation Script Reference

### Bash: `scripts/setup_and_run.sh`

```bash
bash scripts/setup_and_run.sh [options]
```

| Option | Description |
|--------|-------------|
| `--api <url>` | Override the backend URL shared with Expo (defaults to `http://localhost:<backend-port>` when backend runs locally). |
| `--expo-port <port>` | Set Expo dev server port (default `8083`). |
| `--backend-port <port>` | Set backend port (default `3001`). |
| `--backend-wait <seconds>` | Seconds to wait for backend health check (default `60`). |
| `--skip-install` | Skip `npm install` for both projects. |
| `--install-only` | Install dependencies and exit without starting servers. |
| `--backend-only` | Run only the backend in the foreground. |
| `--expo-only` | Run only the Expo dev server (assumes backend is reachable). |

### PowerShell: `scripts/setup_and_run.ps1`

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_and_run.ps1 [options]
```

| Option | Description |
|--------|-------------|
| `-ApiUrl <url>` | Override API base URL sent to Expo. |
| `-ExpoPort <port>` | Expo dev server port (default `8083`). |
| `-BackendPort <port>` | Backend port (default `3001`). |
| `-BackendWaitSeconds <seconds>` | Health check timeout (default `60`). |
| `-SkipInstall` | Skip dependency installation. |
| `-InstallOnly` | Install dependencies and exit. |
| `-BackendOnly` | Start only the backend in the foreground. |
| `-ExpoOnly` | Start only Expo (backend must already be running). |

The scripts verify that `node`, `npm`, `npx`, and (where applicable) `curl` are available before proceeding. When the backend runs in the background, logs are written to `backend.log` at the repository root.

---

## Manual Workflow (If You Prefer)

1. **Start the backend**
   ```bash
   cd backend
   npm install           # skip if already installed
   PORT=3001 node server.js
   ```

2. **Start Expo**
   ```bash
   cd lexical-expo-app
   npm install           # skip if already installed
   EXPO_PUBLIC_API_URL=http://<your_machine_ip>:3001 npx expo start --port 8083
   ```

3. **Test the API directly**
   ```bash
   curl http://<your_machine_ip>:3001/api/health
   curl "http://<your_machine_ip>:3001/api/search?word=example"
   ```

Use `--tunnel` with `npx expo start` or a service such as `ngrok` if your device cannot reach the backend over the local network.

---

## Configuration Notes

- `backend/.env`
  - `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`, `PORT`
  - Do **not** commit real credentials. The provided `.env` is for local demos only.
- `EXPO_PUBLIC_API_URL`
  - Set this environment variable when launching Expo so the client can hit the correct backend URL. The automation scripts handle this automatically.
- CORS is enabled broadly for development. Restrict it before deploying to production.

---

## Troubleshooting

- **Expo app cannot reach backend**
  - Ensure both devices are on the same Wi-Fi.
  - Confirm the backend health endpoint responds: `curl http://<ip>:3001/api/health`.
  - Use the `--api`/`-ApiUrl` flag to point Expo at a tunnel or remote host.
- **Port already in use**
  - Pass `--backend-port`/`-BackendPort` or `--expo-port`/`-ExpoPort` to change ports.
- **Dependency installation fails**
  - Make sure Node.js 18+ is installed and you have an up-to-date npm.
  - Delete `node_modules` and re-run the script if needed.
- **MySQL authentication errors**
  - Double-check `backend/.env` and confirm that the user has READ access to the target schema.

---

## Additional Documentation

- Long-form technical plan: see `docs/TECHNICAL_ROADMAP.md` for architecture, testing, deployment, and roadmap guidance.
- Future enhancements may include automated tests, CI workflows, richer dictionary data, and production deployment scripts.

---

## Security & Housekeeping

- Keep `.env` files out of source control; rotate credentials used for demos.
- Review backend logs in `backend.log` for connection issues when using the automation scripts.
- When preparing for git, add a top-level `.gitignore` (if you have not already) to ignore `node_modules`, `.env`, Expo caches, and build artifacts.

---

Happy hacking! Open an issue or reach out if you need help extending the project.
