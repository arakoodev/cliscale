# **CLI Scale — Ephemeral CLI Agents on Kubernetes**

> Run short-lived CLI jobs on Kubernetes with WebSocket streaming, PostgreSQL session management, and API key authentication.
> Access everything via a single load balancer IP address - no domain required!

## 🎯 Quick Start

**Get your load balancer IP and start using it:**

```bash
# 1. Get load balancer IP (after deployment)
export LB_IP=$(kubectl get ingress cliscale-ingress -n ws-cli -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export API_KEY=$(kubectl get secret cliscale-api-key -n ws-cli -o jsonpath='{.data.API_KEY}' | base64 -d)

# 2. Create a session
RESPONSE=$(curl -X POST "http://$LB_IP/api/sessions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"code_url": "https://github.com/user/repo/tree/main/folder", "command": "npm start"}')

# 3. Get the terminal URL (copy-paste into browser)
echo $RESPONSE | jq -r '.terminalUrl' | sed "s/YOUR_LB_IP/$LB_IP/"

# Or manually: Open the terminalUrl from response, replacing YOUR_LB_IP with your actual IP
```

**That's it!** No DNS, no domains, no TLS required for testing.

---

## 🚀 Overview

This stack runs **ephemeral CLI agents** inside Kubernetes Jobs with:
- **API Key Authentication**: Simple Bearer token auth
- **WebSocket Streaming**: Live terminal output via xterm.js + tmux
- **Session Management**: PostgreSQL tracks sessions and prevents JWT replay
- **One Load Balancer**: Single IP address handles all traffic
- **Auto-exit**: Containers exit when commands complete
- **Full Terminal Emulation**: tmux provides 100k line scrollback, mouse support, colors

### How It Works

1. **Create Session**: Call `POST http://LB_IP/api/sessions` with API key
2. **Spawn Job**: Controller creates a Kubernetes Job to run your code
3. **Get URL**: Response includes pre-composed `terminalUrl` (just replace YOUR_LB_IP)
4. **Open Terminal**: Copy-paste the URL into your browser
5. **Live Execution**: Command runs immediately in tmux, streams to browser via ttyd
6. **Auto-cleanup**: Container exits when command completes, Job cleans up via TTL

---

## ✨ Key Features

### Terminal Experience
- **Full Terminal Emulation**: tmux provides proper terminal with colors, cursor movement, interactive prompts
- **100k Line Scrollback**: Full command output history available
- **Mouse Support**: Scroll, select, copy text with mouse
- **Live Updates**: See output as it happens, no polling needed
- **Persistent Sessions**: Disconnect and reconnect, command keeps running

### Execution
- **Immediate Start**: Commands execute right away (no waiting for browser connection)
- **Auto-exit**: Containers exit when commands complete (configurable)
- **Exit Code Propagation**: Container returns command's actual exit code
- **GitHub Integration**: Direct support for GitHub tree URLs (`github.com/user/repo/tree/main/folder`)
- **Flexible Commands**: Run any shell command, script, or CLI tool

### Security
- **API Key Authentication**: Simple Bearer token for session creation
- **Short-lived JWTs**: RS256 signed tokens with 5-minute expiry
- **Replay Prevention**: One-time JTI tokens prevent reuse
- **Network Isolation**: Jobs run in isolated pods with NetworkPolicy
- **Rate Limiting**: 5 sessions per minute per IP

### Operations
- **One Load Balancer**: Single entry point, no per-pod exposure
- **Auto-cleanup**: TTL-based Job cleanup (default: 5 minutes after completion)
- **Database Migrations**: Automated via Helm hooks
- **Horizontal Scaling**: Controller and gateway scale independently
- **Zero DNS Required**: Works with IP address only

---

## 🧩 Architecture

```
                    http://YOUR_LB_IP
                           │
              ┌────────────┴────────────┐
              │  GCE Load Balancer      │
              │  (Path-based routing)   │
              └────────────┬────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   /api/* routes      /ws/* routes    /.well-known/*
        │                  │                  │
        ▼                  ▼                  │
  ┌──────────┐      ┌──────────┐            │
  │Controller│      │ Gateway  │◄───────────┘
  │ - Auth   │      │- xterm.js│
  │ - Jobs   │      │- WS Proxy│
  └─────┬────┘      └─────┬────┘
        │                  │
        └────────┬─────────┘
                 ▼
        ┌──────────────────┐
        │  PostgreSQL      │
        │  - Sessions      │
        │  - JTIs          │
        └──────────────────┘
```

### Path-Based Routing

The load balancer routes by URL path:

| Request | Backend |
|---------|---------|
| `POST /api/sessions` | Controller (creates session) |
| `GET /api/sessions/{id}` | Controller (get session info) |
| `GET /.well-known/jwks.json` | Controller (JWT verification) |
| `GET /ws/{sessionId}?token={jwt}` | Gateway (serves xterm.js HTML) |
| `WS /ws/{sessionId}` | Gateway (WebSocket proxy to runner) |

### Architecture Design Notes

**Q: Why does ttyd serve HTML if gateway also serves xterm.js?**

The gateway serves xterm.js HTML to browsers, but ttyd in runner pods also has HTML serving capability. This is intentional:
- **Production**: Browsers connect through gateway (secure, with JWT validation)
- **Debugging**: Can directly connect to ttyd on pod IP for troubleshooting
- **Simplicity**: ttyd comes with terminal UI by default, no extra configuration needed

**Q: Why not remove gateway and connect directly to runner pods?**

Security! The gateway provides:
- JWT verification against controller's JWKS endpoint
- One-time JTI consumption (prevents replay attacks)
- Session validation from database
- Centralized rate limiting and monitoring

Direct connection to runner pods would bypass all security controls.

---

## ⚙️ Components

### 1. Controller
- Validates API key from `Authorization: Bearer {key}`
- Creates Kubernetes Jobs (one per session)
- Mints short-lived RS256 session JWTs with one-time JTI
- Exposes JWKS endpoint for JWT verification
- Rate limiting: 5 requests/min per IP

### 2. Gateway (Security Layer + Terminal UI)
- **Security First**: Verifies session JWTs via controller's JWKS endpoint
- **Replay Prevention**: Consumes one-time JTI (prevents token reuse)
- **Terminal UI**: Serves self-hosted xterm.js at `/ws/{sessionId}?token={jwt}`
- **WebSocket Proxy**: Proxies authenticated connections to runner pods
- **Scalable**: Stateless, scales horizontally

**Why not connect directly to runner pods?**
- Runner pods are ephemeral and not exposed externally
- Gateway provides centralized authentication/authorization
- One entry point simplifies network policies and monitoring

### 3. Runner (Execution Environment)
- **tmux + ttyd**: Runs command in tmux session, serves WebSocket on port 7681
- **Code Download**: Supports GitHub tree URLs (`github.com/user/repo/tree/main/folder`)
- **Dependency Installation**: Runs `npm install` (or custom install command)
- **Auto-exit**: Container exits when command completes (configurable)
- **Exit Code Propagation**: Returns command's actual exit code
- **Terminal Features**: Full terminal emulation with 100k line scrollback, mouse support
- **Job Isolation**: Runs in isolated Kubernetes Job with NetworkPolicy
- **Auto-cleanup**: TTL-based cleanup after completion

### 4. PostgreSQL (Cloud SQL)
- Stores session metadata (`sessionId` → `podIP` mapping)
- Tracks one-time JTIs to prevent JWT replay
- Auto-prunes expired sessions
- **Uses Knex.js for migrations**: Version-controlled schema changes

---

## ☸️ Deployment

### Prerequisites

```bash
# Install tools
brew install skaffold  # or: curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-darwin-amd64
gcloud components install kubectl

# Set up GCP project
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID
```

### One-Command Deployment

```bash
# Deploy everything (builds images via Cloud Build, deploys via Helm)
skaffold run \
  --default-repo=us-central1-docker.pkg.dev/$PROJECT_ID/apps \
  --profile=staging
```

**What this does:**
1. Builds controller, gateway, and runner Docker images
2. Pushes to Artifact Registry via Cloud Build
3. **Runs database migrations automatically** (Helm pre-install hook)
4. Deploys controller and gateway pods
5. Creates a GCE load balancer
6. ✅ Ready to use!

**Migrations are fully automated!** Skaffold uses Helm with `wait: true`, which means:
- Migrations run via Helm hook before deployment
- Skaffold waits for the migration Job to complete
- If migrations fail, deployment stops automatically
- Safe to run multiple times (Knex tracks applied migrations)

### Get Your Load Balancer IP

```bash
# Wait for load balancer to provision (5-10 minutes)
kubectl get ingress cliscale-ingress -n ws-cli -w

# Once ADDRESS appears, export it
export LB_IP=$(kubectl get ingress cliscale-ingress -n ws-cli -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

### Get Your API Key

```bash
export API_KEY=$(kubectl get secret cliscale-api-key -n ws-cli -o jsonpath='{.data.API_KEY}' | base64 -d)
echo "API Key: $API_KEY"
```

---

## 🧪 Testing

### Create a Session

```bash
curl -X POST "http://$LB_IP/api/sessions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "code_url": "https://github.com/arakoodev/cliscale/tree/main/sample-cli",
    "command": "node index.js run",
    "prompt": "Hello!",
    "install_cmd": "npm install"
  }'
```

**Response:**
```json
{
  "sessionId": "abc-123-def-456",
  "wsUrl": "/ws/abc-123-def-456",
  "token": "eyJhbGc...",
  "terminalUrl": "http://YOUR_LB_IP/ws/abc-123-def-456?token=eyJhbGc..."
}
```

### Open Terminal

Just copy-paste the `terminalUrl` from the response:
```
http://YOUR_LB_IP/ws/abc-123-def-456?token=eyJhbGc...
```

Replace `YOUR_LB_IP` with your actual load balancer IP and open in browser!

✅ Terminal loads automatically
✅ Connects via WebSocket
✅ Streams live output

### Supported Code URLs

- **GitHub tree**: `https://github.com/owner/repo/tree/branch/folder`
- **Zip**: `https://example.com/code.zip`
- **Tarball**: `https://example.com/code.tar.gz`
- **Git repo**: `https://github.com/owner/repo.git`

---

## 🔒 Security

| Layer | Mechanism |
|-------|-----------|
| API Access | API key (Bearer token from K8s secret) |
| Session Access | Short-lived RS256 JWT with one-time JTI |
| Gateway | JWT verification + JTI replay prevention |
| Runner | Isolated Job with NetworkPolicy + TTL cleanup |
| Database | Private IP, unlogged tables, auto-expiry |
| Rate Limiting | 5 req/min per IP for session creation |

**Recommended Hardening:**
- Use Cloud KMS for JWT signing keys
- Enable VPC-SC for additional isolation
- Add Cloud Armor for DDoS protection
- Validate code URLs against allowlists

---

## ❓ FAQ

### Q: How do I get the terminal URL?
The API response includes a `terminalUrl` field that's pre-composed:
```json
{
  "terminalUrl": "http://YOUR_LB_IP/ws/{sessionId}?token={jwt}"
}
```
Just replace `YOUR_LB_IP` with your load balancer IP and open in browser!

### Q: Does the command start immediately?
**YES!** Commands start running as soon as the container starts (in a tmux session). You don't need to connect with a browser first. If you connect later, you'll see the output from where the command currently is.

### Q: What happens when the command finishes?
The container automatically exits (configurable via `exitOnJob: "false"` in Helm values). The Kubernetes Job then cleans up after the TTL (default: 5 minutes).

### Q: Can I scroll back through the output?
**YES!** tmux provides 100k lines of scrollback buffer. You can scroll up to see all previous output.

### Q: Do I need a domain?
**NO.** Use the load balancer IP directly: `http://34.120.45.67`

### Q: Can I add a domain later?
**YES.** Set DNS A record to LB IP, then:
```bash
skaffold run --set-value ingress.hostname=cliscale.yourdomain.com
```

### Q: Does WebSocket work over HTTP (not HTTPS)?
**YES.** WebSocket works fine over HTTP. Use `ws://` protocol.

### Q: How do I enable HTTPS?
You need a domain first, then add cert-manager. See DEPLOYMENT.md.

### Q: What's the difference between LB IP and CONTROLLER_URL?
- **LB IP** (`http://34.120.45.67`): External access - YOU use this
- **CONTROLLER_URL** (`http://cliscale-controller.ws-cli.svc.cluster.local`): Internal K8s DNS - pods use this

### Q: How long do JWTs last?
About 5 minutes. They're single-use (JTI is consumed on first WebSocket connection).

### Q: Where is the xterm.js frontend?
Embedded in the gateway. No separate deployment needed.

### Q: How do I run database migrations?
**Migrations run automatically!** Helm hooks run migrations before every deployment.

For Kubernetes clusters, see [MIGRATIONS_K8S.md](./MIGRATIONS_K8S.md) for:
- How automatic migrations work
- Running migrations manually
- Troubleshooting migration failures
- Rollback procedures

For local development, see [controller/MIGRATIONS.md](./controller/MIGRATIONS.md).

### Q: What happened to db/schema.sql?
Now using Knex migrations in `controller/src/migrations/`. Version-controlled and easier to manage.

---

## 📂 Project Structure

```
cliscale/
├── controller/           # API + job spawning
│   ├── src/
│   │   ├── migrations/   # Knex database migrations
│   │   └── tests/        # Jest tests
│   ├── knexfile.js       # Knex configuration
│   └── MIGRATIONS.md     # Migration documentation
├── ws-gateway/           # WebSocket proxy + xterm.js serving
├── runner/               # Job container (downloads code, runs CLI)
├── cliscale-chart/       # Helm chart
├── skaffold.yaml         # Build & deploy config
└── sample-cli/           # Example CLI to run
```

---

## 🔧 Development

```bash
# Live reload during development (migrations run automatically on every deployment)
skaffold dev --port-forward \
  --default-repo=us-central1-docker.pkg.dev/$PROJECT_ID/apps \
  --profile=dev
```

**Note:** Skaffold automatically runs database migrations via Helm hooks before deploying changes. You'll see migration logs in the Skaffold output.

### Database Migrations

**Migrations run automatically** with Skaffold! But you can also run them manually for local development:

```bash
# Run pending migrations (local development)
cd controller && npm run migrate:latest

# Create new migration
cd controller && npm run migrate:make create_my_table

# Rollback last migration
cd controller && npm run migrate:rollback

# View migration logs in Kubernetes
kubectl logs -n ws-cli -l app.kubernetes.io/component=migration --tail=100
```

**Skaffold Integration:**
- `skaffold dev`: Runs migrations on every code change
- `skaffold run`: Runs migrations once during deployment
- Migrations run via Helm pre-install/pre-upgrade hooks
- Skaffold waits for migrations to complete before deploying pods
- Safe to deploy multiple times (Knex skips already-applied migrations)

See **[MIGRATIONS_K8S.md](./MIGRATIONS_K8S.md)** for Kubernetes migration guide.
See **[controller/MIGRATIONS.md](./controller/MIGRATIONS.md)** for local development guide.

---

## 📚 Documentation

- **[DEPLOYMENT.md](./DEPLOYMENT.md)**: Detailed deployment guide
- **[MIGRATIONS_K8S.md](./MIGRATIONS_K8S.md)**: Kubernetes migration guide (automatic + manual)
- **[controller/MIGRATIONS.md](./controller/MIGRATIONS.md)**: Local development migration guide
- **[HELM_PLAN.md](./HELM_PLAN.md)**: Security review
- **[CODE_REVIEW_FINDINGS.md](./CODE_REVIEW_FINDINGS.md)**: Implementation verification

---

## ✅ Quick Recap

| Step | Command |
|------|---------|
| Deploy | `skaffold run --default-repo=...` |
| Get IP | `kubectl get ingress cliscale-ingress -n ws-cli` |
| Get API Key | `kubectl get secret cliscale-api-key -n ws-cli -o jsonpath='{.data.API_KEY}' \| base64 -d` |
| Create Session | `curl -X POST http://$LB_IP/api/sessions -H "Authorization: Bearer $API_KEY" ...` |
| Open Terminal | `http://$LB_IP/ws/{sessionId}?token={jwt}` |

**No domain required. No TLS required. Just works.** 🎉
