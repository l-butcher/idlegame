# SQL Run Order & Verification Checklist

## 1 — Execution order

Run the three files **in this exact sequence** inside the Supabase SQL Editor (or via `psql`).
Each file depends on objects created by the previous one.

| Step | File | What it does |
|------|------|-------------|
| **1** | `supabase/schema.sql` | Creates 21 tables (5 static + 16 player-owned), 15 indexes, enables RLS on every table, and creates 69 policies. |
| **2** | `supabase/seed.sql` | Populates the 5 static/content tables: `base_types` (4 rows), `items` (22 rows), `dungeon_tiers` (25 rows), `idle_production_rules` (8 rows), `ship_upgrade_defs` (6 rows). |
| **3** | `supabase/rpc.sql` | Creates 5 internal helper functions and 10 public `SECURITY DEFINER` RPC functions. |

> **Local dev shortcut** — `supabase db reset` applies the migrations in
> `supabase/migrations/` and then seeds from `supabase/seed.sql` automatically.
> If you use this flow, only `rpc.sql` needs a corresponding migration file
> (one is already provided at `supabase/migrations/…_rpc_functions.sql`).

---

## 2 — Verification checklist

Work through these checks after each step.

### After Step 1 (`schema.sql`)

- [ ] **1. Table count** — 21 tables exist in `public` schema.
  ```sql
  SELECT count(*) FROM pg_tables WHERE schemaname = 'public';
  -- expect: 21
  ```
- [ ] **2. Static tables present** — `base_types`, `items`, `dungeon_tiers`, `idle_production_rules`, `ship_upgrade_defs` all appear in the Table Editor.
- [ ] **3. RLS enabled everywhere** — Every table shows the shield icon in Studio, or:
  ```sql
  SELECT count(*) FROM pg_policies WHERE schemaname = 'public';
  -- expect: 69
  ```
- [ ] **4. Indexes created** — 15 custom indexes exist.
  ```sql
  SELECT count(*) FROM pg_indexes
  WHERE schemaname = 'public' AND indexname LIKE 'idx_%';
  -- expect: 15
  ```

### After Step 2 (`seed.sql`)

- [ ] **5. base_types rows** — 4 rows (earth, moon, asteroid, europa).
  ```sql
  SELECT id FROM base_types ORDER BY sort_order;
  ```
- [ ] **6. items rows** — 22 rows spanning `currency`, `resource`, `ship_part`, and `misc` categories.
  ```sql
  SELECT category, count(*) FROM items GROUP BY category ORDER BY category;
  -- currency: 1, misc: 6, resource: 7, ship_part: 8
  ```
- [ ] **7. dungeon_tiers rows** — 25 rows, tiers 1–25.
  ```sql
  SELECT min(tier), max(tier), count(*) FROM dungeon_tiers;
  -- 1, 25, 25
  ```
- [ ] **8. idle_production_rules rows** — 8 rules, all for `earth`.
  ```sql
  SELECT base_type_id, count(*) FROM idle_production_rules GROUP BY base_type_id;
  -- earth: 8
  ```

### After Step 3 (`rpc.sql`)

- [ ] **9. Functions created** — 15 functions in the `public` schema (5 helpers + 10 RPCs).
  ```sql
  SELECT count(*) FROM information_schema.routines
  WHERE routine_schema = 'public' AND routine_type = 'FUNCTION';
  -- expect: 15
  ```
- [ ] **10. Smoke-test `rpc_bootstrap_player`** — Sign up a test user via Auth, then call the RPC. It should return a JSONB snapshot containing a profile, earth base, 9 skills, a ship, and starting unlocks.
  ```sql
  SELECT rpc_bootstrap_player();
  ```
  _(Must be called as an authenticated user — use the Supabase client or set `request.jwt.claims` in a psql session.)_

---

## 3 — Troubleshooting

### RLS blocks all reads / writes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SELECT` on a static table returns 0 rows via the API | Request is missing or using an invalid JWT. | Pass a valid `Authorization: Bearer <token>` header. Static-table policies require the `authenticated` role. |
| `INSERT` into a player table fails with `new row violates row-level security policy` | The `user_id` in the payload does not match `auth.uid()`. | Ensure the client sends `user_id` equal to the signed-in user's ID, or use the RPC functions (they run as `SECURITY DEFINER` and manage `user_id` internally). |
| Queries work in the SQL Editor but fail from the API | The SQL Editor runs as `postgres` (superuser), which bypasses RLS. API requests run as `authenticated` or `anon`. | This is expected. Test with a real JWT from the API to validate RLS behaviour. |

### Missing tables or columns

| Symptom | Cause | Fix |
|---------|-------|-----|
| `relation "public.base_types" does not exist` | `schema.sql` was not run, or was run in the wrong database. | Re-run Step 1. If using migrations, run `supabase db reset`. |
| `column "X" does not exist` inside an RPC call | `rpc.sql` was created against a different version of the schema. | Drop all functions (`DROP FUNCTION IF EXISTS <name>`) and re-run Step 3, or do a full `supabase db reset`. |
| Seed inserts fail with `violates foreign key constraint` | `seed.sql` was run before `schema.sql`, or tables were dropped without re-creating. | Always run in order: schema → seed → rpc. |

### Function not found

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Could not find the function public.rpc_bootstrap_player without arguments` via PostgREST | `rpc.sql` was never applied, or PostgREST hasn't reloaded its schema cache. | Verify the function exists (`\df rpc_bootstrap_player` in psql). If it exists, send `NOTIFY pgrst, 'reload schema'` or restart the `kong` / `rest` container. Locally: `supabase stop && supabase start`. |
| `function _build_player_snapshot(uuid) does not exist` | `rpc.sql` was partially applied; helper functions at the top of the file were skipped. | Re-run the entire `rpc.sql` file from the beginning. |
| `permission denied for function rpc_*` | The function was created without `SECURITY DEFINER`, or the `authenticated` role was not granted `EXECUTE`. | All RPC functions are `SECURITY DEFINER` and callable by any authenticated user by default. Re-run `rpc.sql` to restore the correct definitions. |
