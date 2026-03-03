# AGENTS.md

## Cursor Cloud specific instructions

### Project overview
This is a Supabase-based backend for a mobile idle + dungeon ladder game. The codebase is in early stage — it contains design docs (`docs/`) and empty SQL stubs (`supabase/schema.sql`, `supabase/rpc.sql`, `supabase/seed.sql`). The backend runs entirely on Supabase (Postgres + Auth + RPC).

### Prerequisites (already installed in the VM snapshot)
- **Docker** — required by the Supabase CLI to run the local stack.
- **Supabase CLI** (`supabase` v2.75+) — installed at `/usr/local/bin/supabase`.
- **PostgreSQL client** (`psql`) — for direct DB access.

### Starting the local Supabase stack
```bash
# Ensure Docker daemon is running first
sudo dockerd &>/tmp/dockerd.log &
sleep 3
sudo chmod 666 /var/run/docker.sock

# Start Supabase (pulls/starts ~12 containers)
cd /workspace && supabase start
```
First start takes ~2–3 minutes (image pulls). Subsequent starts are faster.

### Key local endpoints (after `supabase start`)
| Service        | URL                                       |
|---------------|-------------------------------------------|
| API (Kong)     | http://127.0.0.1:54321                    |
| REST (PostgREST) | http://127.0.0.1:54321/rest/v1         |
| Studio UI      | http://127.0.0.1:54323                    |
| Postgres       | postgresql://postgres:postgres@127.0.0.1:54322/postgres |
| Mailpit (email) | http://127.0.0.1:54324                   |

Run `supabase status` to see all endpoints and keys.

### Common development commands
| Task              | Command                      |
|-------------------|------------------------------|
| Lint DB schema    | `supabase db lint`           |
| Reset DB (re-apply migrations + seed) | `supabase db reset` |
| Check status      | `supabase status`            |
| Stop stack        | `supabase stop`              |
| Direct SQL access | `PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres` |

### Gotchas
- The Supabase CLI cannot be installed globally via `npm install -g supabase`; use the direct binary from GitHub releases instead.
- In the Cloud Agent VM (Docker-in-Docker), you must configure `fuse-overlayfs` as the Docker storage driver and switch to `iptables-legacy` before starting dockerd.
- After starting dockerd, run `sudo chmod 666 /var/run/docker.sock` so the `supabase` CLI (running as `ubuntu`) can access Docker without sudo.
- The `supabase start` command must be run with direct Docker socket access (not via sudo) for health checks to work properly.
- `supabase db reset` re-applies migrations and seeds from `supabase/seed.sql`; it takes ~30s.
