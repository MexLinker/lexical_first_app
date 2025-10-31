# Technical Roadmap — Lexical Expo App + MySQL Backend

This document describes the end‑to‑end technical plan, covering architecture, data flow, environments, testing, deployment, operations, and future evolution for the project.

## Overview
- Client: React Native (Expo), using `expo-router` and TypeScript.
- Backend: Node.js + Express, MySQL driver, REST API.
- Database: MySQL schema with an `english_words` table (and future tables for enrichment).
- Networking: LAN development (preferred), optional tunnel for remote devices, CORS enabled for web.

## Architecture
- Mobile/Web Client (Expo)
  - Pages built with `expo-router` under `app/` and `(tabs)/`.
  - `constants/backend.ts` resolves `API_BASE_URL` from `EXPO_PUBLIC_API_URL` or auto‑detects Expo host IP.
  - Fetches `GET /api/search?word=<word>` for search results.

- Backend (Express)
  - Loads environment from `.env` (e.g., `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `PORT`).
  - Connects to MySQL; inspects schema at startup for visibility.
  - Endpoints:
    - `GET /api/health` → `{ ok: true }` (service liveness)
    - `GET /api/search?word=<word>` → `{ word, results: [ { source, word, definitions, examples } ] }`
  - CORS policy: permissive (`Access-Control-Allow-Origin: *`) for development.

- Database (MySQL)
  - Primary schema: `english_words_db.english_words` (columns include `word`, `definitions`, etc.).
  - Read‑only queries for search; future tables can provide synonyms, frequency, or phonetics.

## Data Flow
1. User enters a word in the Expo app.
2. Client builds URL via `searchUrl(word)` and fetches JSON from backend.
3. Backend queries MySQL and shapes results uniformly.
4. Client renders definitions/examples in a simple list.

## Environments & Config
- Development (LAN): Expo dev server on `exp://<LAN-IP>:<port>`; backend on `http://<LAN-IP>:3001`.
- Tunnel/Remote Testing: Use Expo tunnel or `ngrok` to expose backend if devices cannot reach LAN.
- Environment variables:
  - Backend `.env`: `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `PORT` (defaults to 3001).
  - Client: `EXPO_PUBLIC_API_URL` (optional; overrides auto detection).

## Local Development Workflow
- Backend
  - `PORT=3001 node server.js` (or `npm start` if added later)
  - Confirm health: `curl http://<LAN-IP>:3001/api/health`
  - Sample search: `curl 'http://<LAN-IP>:3001/api/search?word=example'`
- Client
  - `EXPO_PUBLIC_API_URL=http://<LAN-IP>:3001 npx expo start --port 8083`
  - Scan QR with Expo Go, or open web at `http://localhost:8083`.

## Testing Strategy
- Unit tests (future):
  - Backend route handlers return shapes as expected.
  - DB layer stubs for search queries.
- Integration (future):
  - Spin up test DB or use `docker-compose` with MySQL.
  - Run API tests against seeded tables.
- Client tests (future):
  - Component rendering and fetch path behavior under various env settings.

## Security & Secrets
- Do not commit `.env`; provide `.env.example` with placeholders.
- Restrict CORS in production (specific origins only).
- Consider rate limiting and input validation on `word`.
- MySQL credentials from environment or secret manager (depending on host).

## CI/CD & Branching
- Branches: `main` (stable), `dev` (integration), feature branches per task.
- Actions (future):
  - Lint and type‑check on PR.
  - Backend tests in Node workflow.
  - Optional: Build Expo web bundle to catch type errors.

## Deployment Plan
- Backend options:
  - Render, Railway, Fly.io, or Docker on a VPS.
  - Provide `PORT`, DB credentials via environment; add health endpoint.
  - Harden CORS, add logging and error handling.
- Database:
  - Managed MySQL (e.g., PlanetScale, RDS) or self‑hosted.
  - Migration scripts or SQL files under `db/` (future).
- Client (mobile):
  - Development via Expo Go.
  - Production: EAS builds for Android/iOS; configure env at build time.
- Client (web):
  - Optional static bundle; ensure CORS alignment with backend.

## Observability & Operations
- Logging:
  - Backend: request logs (method, path, status), DB errors, startup diagnostics.
- Monitoring:
  - Uptime monitoring against `/api/health`.
  - Metrics (future): basic request latency and error counts.
- Error Tracking (future):
  - Sentry for client and backend.

## Performance & Scalability
- DB indexing on `word` column.
- Cache layer (future): simple in‑memory or Redis for frequent words.
- Pagination or limits on results if tables grow.

## Risks & Mitigations
- LAN connectivity issues → use tunnel; ensure same Wi‑Fi.
- CORS blocks in web → backend enables `cors()`; restrict in prod.
- Large payloads → limit response size; compress if needed.

## Roadmap Phases
1. Prototype (complete): basic search, LAN dev, CORS enabled.
2. Hardening: input validation, error handling, logging, env samples.
3. Testing & CI: add unit/integration tests, GitHub Actions.
4. Deployment: host backend & DB; switch client env to production.
5. Enhancements: richer data sources, pronunciation, offline cache, favorites.

## Next Steps
- Add `.env.example` and top‑level `.gitignore` (done in this iteration).
- Document setup in README and consistent start commands.
- Plan CI checks and DB migration scaffolding.