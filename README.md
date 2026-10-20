
# 🐻🦁 Homelab Infrastructure (`ugreen-homelab`)

Infraestructura híbrida de Docker para homelab distribuida entre un **NAS local (UGOS / Linux)** y un **VPS remoto**, gestionada bajo filosofía **GitOps** mediante **Dockhand**.

Las definiciones de los stacks residen en este repositorio organizadas por entorno (`nas/` y `vps/`), mientras que las credenciales y configuraciones sensibles se gestionan de forma segura a través del gestor de secretos de Dockhand (cifrados y nunca versionados en Git).

---

## 🖥️ Especificaciones de Infraestructura

### 🏠 Host Local (NAS)
* **Dispositivo:** Ugreen NAS DXP2800
* **Procesador (CPU):** Intel® N100 (4 núcleos, 4 hilos, hasta 3.40 GHz) con gráficos Intel UHD
* **Memoria RAM:** 8 GB DDR5
* **OS:** Ugreen UGOS Pro
* **Almacenamiento:**
  * 💽 **Almacenamiento masivo (Datos):** 2 × HDD 4 TB en **RAID 1** (espejo para redundancia y tolerancia a fallos)
  * ⚡ **Almacenamiento de aplicaciones:** 1 × SSD 512 GB dedicado al SO, `docker/appdata`, bases de datos y ejecución rápida de servicios

### ☁️ Servidor Cloud (VPS)
* **Tipo:** Máquina Virtual (VPS 2-4-120)
* **Procesador (CPU):** 2 vCores
* **Memoria RAM:** 4 GB
* **OS:** Ubuntu 24.04
* **Almacenamiento:** 120 GB NVMe SSD
* **Rol:** Nodo perimetral para tunelización inversa y servicios públicos

---

## 🏗️ Estructura del Repositorio

```text
ugreen-homelab/
├── 🌐 global.env            # Variables globales compartidas por los stacks
├── 🏠 nas/                  # Servicios locales alojados en el almacenamiento doméstico
│   ├── 🛡️ adguard/
│   ├── 📊 beszel/
│   ├── 💻 code-server/
│   ├── 📈 dbt-financial/
│   ├── 📋 dozzle/
│   ├── 📑 homepage/
│   ├── 📸 immich/
│   ├── 📺 jellyfin-iptv/
│   ├── ⚙️ n8n/
│   ├── 📓 obsidian-sync/
│   ├── 🦎 pangolin-agent/
│   ├── 🐘 postgres/
│   ├── ⚡ speedtest-tracker/
│   ├── 🌐 tailscale/
│   ├── 🐧 ubuntu-terminal/
│   ├── 🚦 uptime-kuma/
│   ├── 🔒 vaultwarden/
│   └── 🔍 watchyourlan/
└── ☁️ vps/                  # Servicios en servidor perimetral cloud
    ├── ⚓ hawser/
    └── 🦎 pangolin/
```

> **Seguridad:** Los archivos `.env` reales están excluidos mediante `.gitignore`. Cada stack incluye un archivo `.env.example` como plantilla de referencia.

---

## 🛠️ Servicios Desplegados

### 🏠 Local NAS (`nas/`)

| Servicio | Categoría | Descripción |
| :--- | :--- | :--- |
| **🛡️ AdGuard Home** | Red y DNS | Servidor DNS y bloqueo de publicidad/telemetría en red local. |
| **📊 Beszel** | Métricas | Agente local para monitorización de hardware y recursos. |
| **💻 Code Server** | Desarrollo | Entorno VS Code accesible vía web para mantenimiento y scripts. |
| **📈 dbt-financial** | Datos | Pipeline y transformaciones de datos para análisis financiero. |
| **📋 Dozzle** | Administración | Visualizador ligero de logs de contenedores Docker en tiempo real. |
| **📑 Homepage** | Dashboard | Panel de control centralizado con enlaces e integraciones del homelab. |
| **📸 Immich** | Multimedia | Backup y gestión de biblioteca de fotos/vídeos con aceleración por hardware. |
| **📺 Jellyfin IPTV** | Multimedia | Servidor de streaming y gestión de canales IPTV. |
| **⚙️ n8n** | Automatización | Motor de flujos de trabajo e integraciones entre servicios. |
| **📓 Obsidian Sync** | Productividad | Backend CouchDB para sincronización cifrada de notas (*LiveSync*). |
| **🦎 Pangolin Agent** | Red | Agente (*Newt*) para tunelización y exposición segura hacia el VPS. |
| **🐘 PostgreSQL** | Base de datos | Motor relacional centralizado para servicios internos. |
| **⚡ Speedtest Tracker** | Rendimiento | Auditoría periódica de ancho de banda, ping y calidad de red. |
| **🌐 Tailscale** | Red / VPN | Enlace de malla cifrado configurado como nodo de salida (*Exit Node*). |
| **🐧 Ubuntu Terminal** | Utilidades | Contenedor con entorno Ubuntu para tareas administrativas auxiliares. |
| **🚦 Uptime Kuma** | Monitorización | Supervisión de disponibilidad y alertas de los servicios locales. |
| **🔒 Vaultwarden** | Seguridad | Gestor de contraseñas autoalojado compatible con Bitwarden. |
| **🔍 WatchYourLAN** | Red | Escáner y auditoría de dispositivos conectados a la LAN. |

---

### ☁️ Cloud VPS (`vps/`)

| Servicio | Categoría | Descripción |
| :--- | :--- | :--- |
| **🦎 Pangolin** | Red / Proxy | Punto de entrada perimetral y túnel inverso para acceso exterior. |
| **⚓ Hawser** | Utilidades | Agente / herramienta de orquestación y soporte para el entorno VPS. |

---

## 🌍 Configuración Compartida (`global.env`)

Plantilla de variables transversales inyectadas por Dockhand al levantar los contenedores:

| Variable | Propósito | Ejemplo / Tipo |
| :--- | :--- | :--- |
| `PUID` / `PGID` | UID y GID sin privilegios para consistencia en permisos | `1000` / `1000` |
| `TZ` | Zona horaria del sistema | `<TU_ZONA_HORARIA>` |
| `DOCKER_ROOT` | Ruta base de Docker en el almacenamiento del host | `/ruta/a/docker` |
| `APPDATA_PATH` | Ruta de persistencia para datos de aplicaciones | `/ruta/a/docker/appdata` |
| `LOG_MAX_SIZE` / `LOG_MAX_FILE` | Límites globales para rotación de logs de Docker | `<TAM_LOG>` / `<CANT_LOG>` |


---
