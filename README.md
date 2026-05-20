# 🐻🦁 ugreen-homelab

Homelab Docker setup for the **BearsLions** homelab running on a **Ugreen DXP2800** (Intel N100, 8GB RAM).

All stacks are managed via **Dockhand** using a GitOps approach — configuration lives here, secrets stay in Dockhand.

---

## 📁 Repository Structure

```
ugreen-homelab/
├── global.env                  # Shared variables injected into all stacks
├── adguard/
│   └── docker-compose.yml
├── beszel/
│   ├── docker-compose.yml
│   └── .env.example
├── code-server/
│   ├── docker-compose.yml
│   └── .env.example
├── homepage/
│   └── docker-compose.yml
├── immich/
│   ├── docker-compose.yml
│   └── .env.example
├── n8n/
│   ├── docker-compose.yml
│   └── .env.example
├── obsidian-sync/
│   ├── docker-compose.yml
│   └── .env.example
├── pangolin-agent/
│   ├── docker-compose.yml
│   └── .env.example
├── speedtest-tracker/
│   ├── docker-compose.yml
│   └── .env.example
├── tailscale/
│   ├── docker-compose.yml
│   └── .env.example
├── uptime-kuma/
│   └── docker-compose.yml
├── vaultwarden/
│   ├── docker-compose.yml
│   └── .env.example
└── watchyourlan/
    └── docker-compose.yml
```

> `.env` files are **gitignored**. Each stack with secrets includes a `.env.example` as reference.
> Sensitive values are managed via **Dockhand Secrets** (encrypted, never written to disk).

---

## 🌍 Global Configuration (`global.env`)

Shared variables injected into every stack by Dockhand at deploy time.

| Variable | Description |
|---|---|
| `PUID` / `PGID` | User/group ID for LinuxServer images |
| `TZ` | Timezone (`Europe/Madrid`) |
| `DOCKER_ROOT` | Root path (`/volume1/docker`) |
| `APPDATA_PATH` | Persistent data path (`/volume1/docker/appdata`) |
| `GITOPS_PATH` | This repo's path on disk (`/volume1/docker/gitops`) |
| `LOG_MAX_SIZE` / `LOG_MAX_FILE` | Global log rotation limits |
| `DOMAIN` | Base domain (`bearslions.com`) |
| `NAS_IP` | NAS local IP address (`192.168.1.225`) |

---

## 🛠️ Services

### 🛡️ AdGuard Home
**Image:** `adguard/adguardhome:latest`
**IP:** `192.168.1.53` (macvlan)
**Network:** `adguard_macvlan` — dedicated macvlan with fixed IP for DNS
**Secrets:** None.

Network-wide DNS server and ad blocker. Uses a dedicated macvlan network so it can bind to port 53 without conflicts with the host.

```
appdata/adguard/work/    ← runtime data
appdata/adguard/conf/    ← configuration
```

---

### 📊 Beszel
**Images:** `henrygd/beszel` + `henrygd/beszel-agent`
**Port:** `8090` (hub)
**Secrets:** `BESZEL_AGENT_KEY`

System monitoring dashboard with hub-agent architecture. The agent runs in host network mode to collect system metrics; the hub provides the web UI.

| Variable | Description |
|---|---|
| `BESZEL_AGENT_KEY` | Public key for hub-agent authentication |

```
appdata/beszel/hub_data/    ← hub database & config
```

---

### 💻 Code Server
**Image:** `lscr.io/linuxserver/code-server:latest`
**Port:** `8443`
**Secrets:** `WEB_PASSWORD`

VS Code in the browser. Configured with master access to the entire `DOCKER_ROOT`, making it a central editor for all stacks.

| Variable | Description |
|---|---|
| `WEB_PASSWORD` | Web UI login password |

```
appdata/code-server/config/    ← extensions, themes, settings
```

---

### 🏠 Homepage
**Image:** `ghcr.io/gethomepage/homepage:latest`
**Port:** `3005`
**Secrets:** None.

Homelab dashboard. Configuration is file-based inside the config volume. Has read-only access to `docker.sock` for automatic service discovery.

```
appdata/homepage/config/    ← services, widgets, bookmarks config
```

---

### 📸 Immich
**Images:** `immich-server` + `immich-machine-learning` + `postgres` + `valkey`
**Port:** `2283`
**Memory:** 2GB (server) + 2GB (ML) + 1GB (postgres) + 256MB (redis)
**Secrets:** `DB_PASSWORD`, `IMMICH_VERSION`

Self-hosted photo and video management. Configured with OpenVINO hardware acceleration for the Intel N100 iGPU, covering face recognition, CLIP search, and smart albums. PostgreSQL uses the pgvecto.rs extension required by Immich.

| Variable | Description |
|---|---|
| `DB_PASSWORD` | PostgreSQL password |
| `IMMICH_VERSION` | Image tag (default: `release`) |

```
appdata/immich/album/         ← photo & video library
appdata/immich/model-cache/   ← AI models (face recognition, CLIP)
appdata/immich/postgres/      ← database
```

> ⚠️ Immich is under active development. Pin `IMMICH_VERSION` to a specific tag for production stability.

---

### ⚙️ n8n
**Image:** `docker.n8n.io/n8nio/n8n:latest`
**Port:** `5678`
**Secrets:** `N8N_ENCRYPTION_KEY`, `N8N_HOST`, `WEBHOOK_URL`

Workflow automation platform. All credentials stored in n8n are encrypted with `N8N_ENCRYPTION_KEY` — losing this key means losing access to all stored credentials.

| Variable | Description |
|---|---|
| `N8N_ENCRYPTION_KEY` | Encryption key for stored credentials — back this up |
| `N8N_HOST` | Hostname (e.g. `n8n.bearslions.com`) |
| `WEBHOOK_URL` | Public webhook base URL (e.g. `https://n8n.bearslions.com/`) |

```
appdata/n8n/    ← workflows, credentials, settings
```

---

### 📓 Obsidian Sync (CouchDB)
**Image:** `couchdb:3.3.3`
**Port:** `5984`
**Memory limit:** `256MB`
**Secrets:** `COUCHDB_USER`, `COUCHDB_PASSWORD`

Self-hosted CouchDB instance used as a sync backend for Obsidian via the [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) plugin.

| Variable | Description |
|---|---|
| `COUCHDB_USER` | CouchDB admin username |
| `COUCHDB_PASSWORD` | CouchDB admin password |

```
appdata/obsidian-sync/data/      ← CouchDB data
appdata/obsidian-sync/config/    ← CouchDB local config
```

---

### 🦎 Pangolin Agent (Newt)
**Image:** `fosrl/newt:latest`
**Memory limit:** `128MB`
**Secrets:** `PANGOLIN_ENDPOINT`, `NEWT_ID`, `NEWT_SECRET`

Tunnel agent for [Pangolin](https://github.com/fosrl/pangolin), a self-hosted tunneling and reverse proxy solution.

| Variable | Description |
|---|---|
| `PANGOLIN_ENDPOINT` | Pangolin server endpoint URL |
| `NEWT_ID` | Agent ID |
| `NEWT_SECRET` | Agent secret |

---

### 🚀 Speedtest Tracker
**Image:** `lscr.io/linuxserver/speedtest-tracker:latest`
**Port:** `8080`
**URL:** `https://speed.bearslions.com`
**Memory limit:** `512MB`
**Secrets:** `APP_KEY`

Runs scheduled internet speed tests (every hour) and tracks results over time. Uses SQLite as the local database.

| Variable | Description |
|---|---|
| `APP_KEY` | Laravel application key — generate with `echo "base64:$(openssl rand -base64 32)"` |

```
appdata/speedtest-tracker/    ← app config & SQLite database
```

---

### 🔒 Tailscale
**Image:** `tailscale/tailscale:latest`
**Network:** `host`
**Secrets:** `TS_AUTHKEY`

Mesh VPN for secure remote access. Configured as an exit node and subnet router, advertising `192.168.1.0/24` to allow full LAN access from anywhere.

| Variable | Description |
|---|---|
| `TS_AUTHKEY` | Tailscale auth key (generate at tailscale.com/settings/keys) |

```
appdata/tailscale/    ← Tailscale state
```

---

### 📡 Uptime Kuma
**Image:** `louislam/uptime-kuma:1`
**Port:** `3001`
**Secrets:** None — authentication is handled internally by the app.

Self-hosted monitoring tool. Tracks uptime of services, ports, and URLs with alerting support. Has read-only access to `docker.sock` for Docker container monitoring.

```
appdata/uptime-kuma/    ← monitors config & data
```

---

### 🔑 Vaultwarden
**Image:** `vaultwarden/server:latest`
**Port:** `8081`
**Memory limit:** `256MB`
**Secrets:** `SIGNUPS_ALLOWED`, `ADMIN_TOKEN`

Lightweight Bitwarden-compatible password manager server. Signups are disabled by default — enable only when adding new users.

| Variable | Description |
|---|---|
| `ADMIN_TOKEN` | Admin panel access token |
| `SIGNUPS_ALLOWED` | Allow new registrations (`true`/`false`, default: `false`) |

```
appdata/vaultwarden/    ← vault data
```

---

### 🔍 WatchYourLAN
**Image:** `aceberg/watchyourlan:latest`
**Port:** `8841`
**Network mode:** `host` (required for ARP scanning)
**Secrets:** None.

Network scanner that detects all devices on the local network. Runs privileged with `NET_ADMIN` and `NET_RAW` capabilities for ARP scanning.

```
appdata/watchyourlan/   ← device history & config
```

---

## 🔐 Secrets Management

Secrets are **never committed** to this repository.

- Each stack with secrets has a `.env.example` documenting the required variables
- Actual values are set in **Dockhand** (encrypted in its database, injected at deploy time)
- After a Docker-native restart (not via Dockhand), secrets may be lost — redeploy from Dockhand to re-inject them

---

## 🌐 Network

Most stacks connect to a shared external Docker network:

```bash
docker network create bearslions_network
```

Exceptions:
- **AdGuard** — uses a dedicated `adguard_macvlan` network with a fixed IP (`192.168.1.53`) for DNS
- **WatchYourLAN**, **Tailscale**, **Beszel Agent** — use `network_mode: host` for low-level network access

---

## 🚀 Deployment

1. Clone this repo to `/volume1/docker/gitops`
2. Create the shared network:
   ```bash
   docker network create bearslions_network
   ```
3. Import each stack in **Dockhand** pointing to the corresponding folder
4. Set secrets in Dockhand for stacks that require them (see `.env.example` in each folder)
5. Deploy stacks in this order to respect dependencies:
   - AdGuard → Tailscale → Vaultwarden
   - PostgreSQL/Redis → Immich
   - Everything else in any order

---

## 🖥️ Hardware

| Spec | Value |
|---|---|
| Device | Ugreen DXP2800 |
| CPU | Intel N100 |
| RAM | 8GB |
| OS | Ugreen UGOS Pro |