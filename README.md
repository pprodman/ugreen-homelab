# 🐻🦁 ugreen-homelab

Homelab Docker setup for the **BearsLions** homelab running on a **Ugreen DXP2800** (Intel N100, 8GB RAM).

All stacks are managed via **Dockhand** using a GitOps approach — configuration lives here, secrets stay in Dockhand.

---

## 📁 Repository Structure

```
ugreen-homelab/
├── global.env                  # Shared variables injected into all stacks
├── uptime-kuma/
│   └── docker-compose.yml
├── watchyourlan/
│   └── docker-compose.yml
├── code-server/
│   ├── docker-compose.yml
│   └── .env.example
├── obsidian-sync/
│   ├── docker-compose.yml
│   └── .env.example
└── speedtest-tracker/
    ├── docker-compose.yml
    └── .env.example
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
| `DOMAIN` | Base domain for services |
| `NAS_IP` | NAS local IP address |

---

## 🛠️ Services

### 📡 Uptime Kuma
**Image:** `louislam/uptime-kuma:1`
**Port:** `3001`
**Secrets:** None — authentication is handled internally by the app.

Self-hosted monitoring tool. Tracks uptime of services, ports, and URLs with alerting support.

```
appdata/uptime-kuma/    ← monitors config & data
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

### 🚀 Speedtest Tracker
**Image:** `lscr.io/linuxserver/speedtest-tracker:latest`
**Port:** `8080`
**Memory limit:** `512MB`
**Secrets:** `APP_KEY`

Runs scheduled internet speed tests (every hour) and tracks results over time. Uses SQLite as the local database.

| Variable | Description |
|---|---|
| `APP_KEY` | Laravel application key (generate with `base64:...`) |
| `APP_URL` | Public URL for the app (e.g. `http://192.168.1.225:8080`) |

```
appdata/speedtest-tracker/config/    ← app config & SQLite database
```

---

## 🔐 Secrets Management

Secrets are **never committed** to this repository.

- Each stack with secrets has a `.env.example` documenting the required variables
- Actual values are set in **Dockhand** (encrypted in its database, injected at deploy time)
- After a Docker-native restart (not via Dockhand), secrets are lost — redeploy from Dockhand to re-inject them

---

## 🌐 Network

All stacks (except WatchYourLAN) connect to a shared external Docker network:

```bash
docker network create bearslions_network
```

This allows inter-container communication without exposing extra ports.

---

## 🚀 Deployment

1. Clone this repo to `/volume1/docker/gitops`
2. Create `bearslions_network` if it doesn't exist
3. Import each stack in **Dockhand** pointing to the corresponding folder
4. Set secrets in Dockhand for stacks that require them (see `.env.example` in each folder)
5. Deploy

---

## 🖥️ Hardware

| Spec | Value |
|---|---|
| Device | Ugreen DXP2800 |
| CPU | Intel N100 |
| RAM | 8GB |
| OS | Ugreen UGOS Pro |