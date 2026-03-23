# npm-pihole-sync

Auto-sync Nginx Proxy Manager domains to Pi-hole v6 DNS.

Polls NPM for proxy hosts and automatically creates/removes DNS A records in Pi-hole. When you add a domain in NPM, it appears in Pi-hole. When you remove it, it's cleaned up.

## Quick Start

1. Clone and start:
   ```bash
   git clone https://github.com/CajuCLC/npm-pihole-sync.git
   cd npm-pihole-sync
   docker compose up -d npm
   ```

2. Set up NPM:
   - Go to `http://YOUR_IP:81`
   - Login with `admin@example.com` / `changeme`
   - Change your email and password

3. Update `docker-compose.yml` with your credentials:
   ```yaml
   environment:
     NPM_URL: http://npm:81
     NPM_EMAIL: your-new-email
     NPM_PASSWORD: your-new-password
     PIHOLE_URL: http://YOUR_PIHOLE_IP
     PIHOLE_PASSWORD: your-pihole-password
     TARGET_IP: YOUR_NPM_HOST_IP
   ```

4. Start the sync:
   ```bash
   docker compose up -d
   ```

That's it. Add proxy hosts in NPM and DNS records appear in Pi-hole automatically.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NPM_URL` | Yes | — | NPM API URL (use `http://npm:81` if running together) |
| `NPM_EMAIL` | Yes | — | NPM admin email |
| `NPM_PASSWORD` | Yes | — | NPM admin password |
| `PIHOLE_URL` | Yes | — | Pi-hole URL (e.g. `http://192.168.1.100`) |
| `PIHOLE_PASSWORD` | Yes | — | Pi-hole v6 web password |
| `TARGET_IP` | Yes | — | IP address for DNS A records (the host running NPM) |
| `SYNC_INTERVAL` | No | `60` | Seconds between sync checks |
| `SKIP_TLS_VERIFY` | No | `false` | Skip TLS verification |

## How It Works

- Polls NPM API every 60 seconds for proxy host domains
- Compares with last known state — only touches Pi-hole when NPM changes
- Creates DNS A records pointing to `TARGET_IP`
- Removes stale DNS records when proxy hosts are deleted from NPM
- Updates DNS records if `TARGET_IP` changes

## Requires

- Pi-hole v6
- Docker and Docker Compose
