# Smoke Test

End-to-end test that exercises every game RPC against a running Supabase instance.

## Prerequisites

- Node.js ≥ 18
- A running Supabase stack (local via `supabase start`, or a remote project)

## Setup

```bash
npm init -y
npm i @supabase/supabase-js
```

Copy the env template and fill in the values:

```bash
cp .env.example .env
```

| Variable | Where to find it |
|---|---|
| `SUPABASE_URL` | `supabase status` → **API URL** (local default: `http://127.0.0.1:54321`) |
| `SUPABASE_ANON_KEY` | `supabase status` → **Publishable** key |
| `EMAIL` | Any email for the test account (will be created on first run) |
| `PASSWORD` | Any password ≥ 6 characters |

## Run

### Bash / macOS / Linux

```bash
set -a && source .env && set +a
node scripts/smoke_test.mjs
```

Or inline:

```bash
env $(cat .env | xargs) node scripts/smoke_test.mjs
```

### Windows PowerShell

```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
node scripts/smoke_test.mjs
```

## What it does

Runs nine RPCs in order:

1. `rpc_bootstrap_player` — creates or re-hydrates the player
2. `rpc_get_player_snapshot` — reads the full state
3. Waits 5 seconds for idle accrual
4. `rpc_claim_all` — collects produced resources
5. `rpc_start_dungeon_run` (tier 1)
6. `rpc_submit_run_choice` — chooses a path
7. `rpc_submit_multiplier` — sets a 2× multiplier
8. `rpc_complete_dungeon_run` — finishes the run (success)
9. `rpc_get_player_snapshot` — confirms final state

The script prints every response as pretty JSON and exits with code **0** on success or **1** on any failure.
