# Backend Build Spec (Supabase) — V1

## Goal
Implement a server-authoritative backend for the game in requirements_v1.md using Supabase (Postgres + RPC).

## Non-goals (V1)
No IAP, ads, clans, trading, leaderboards, PvP, or social features.

## Tech assumptions
- Supabase Auth for user identity
- Postgres is source of truth
- Client is thin: client requests actions, server computes results
- All player-owned tables use RLS
- Static content tables are readable to authenticated users

## Data model requirements
- Multiple bases per user: earth, moon, asteroid (europa exists as a future unlock target)
- Per-base inventory with caps
- Production rules are data-driven (editable in DB)
- Combat skills only increase via dungeon play
- Dungeon ladder: 25 tiers; must clear highest to unlock next; replay allowed
- Dungeon run stores: tier, start/end, choices, multiplier, outcome, rewards

## Offline rules
- Offline accrual is server-authoritative
- Offline accrual cap = 12 hours
- Accrued resources are granted instantly on login via claim-all (or user-initiated claim)
- No punitive penalties on failure

## Currency
Credits are stored as an item in inventory (item_id = 'credits') unless explicitly changed later.

## Deliverables
1) schema.sql
   - Tables + key fields + constraints
   - RLS policies (minimum viable)
2) rpc.sql
   - Player bootstrap
   - Snapshot fetch
   - Claim-all (per base or all bases)
   - Dungeon: start, submit choice, submit multiplier, complete run (success/fail)
   - Ship: equip part, apply upgrade, unlock base/location
3) seed.sql
   - base_types
   - core items (including 'credits')
   - dungeon_tiers 1..25 (reasonable placeholders)
   - idle production rules (earth only to start)
   - ship_upgrade_defs (placeholders)

## Output rules
- Prefer explicit tables over clever abstractions
- Use SECURITY DEFINER functions for RPC
- Always validate auth.uid() inside RPC
- Return deterministic JSON payloads that a mobile client can consume
- Keep V1 minimal but future-ready