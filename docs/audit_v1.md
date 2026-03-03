# V1 SQL Audit — Prioritized Fixes

## P0 — Concurrency: race conditions that violate constraints

### 1. `rpc_apply_ship_upgrade` — credit deduction TOCTOU

**File:** `supabase/rpc.sql`, lines 793–803

The function reads `quantity` with a plain `SELECT`, checks it, then deducts with a separate `UPDATE`. Two concurrent upgrade calls can both pass the check and drive `quantity` negative, violating `CHECK (quantity >= 0)`.

**Replace lines 792–803:**

```sql
    -- check + deduct credits (atomic)
    UPDATE base_inventory
       SET quantity = quantity - _cost_credits, updated_at = now()
     WHERE base_id = _base_id AND item_id = 'credits'
       AND quantity >= _cost_credits;

    IF NOT FOUND THEN
        SELECT coalesce(bi.quantity, 0) INTO _current_cred
          FROM base_inventory bi
         WHERE bi.base_id = _base_id AND bi.item_id = 'credits';
        RAISE EXCEPTION 'Not enough credits (need %, have %)', _cost_credits, coalesce(_current_cred, 0);
    END IF;
```

---

### 2. `rpc_apply_ship_upgrade` — ship parts deduction TOCTOU

**File:** `supabase/rpc.sql`, lines 810–825

Same pattern: read-check-write on `player_ship_parts.quantity`. Concurrent calls can both pass ownership checks, then both deduct, violating `CHECK (quantity >= 1)` or deleting a row the other transaction still expects.

**Replace lines 810–825:**

```sql
    FOR _part_id, _part_count IN
        SELECT p.value::text, count(*)::int
          FROM jsonb_array_elements_text(_parts_needed) p(value)
         GROUP BY p.value
    LOOP
        IF _part_count = (SELECT sp.quantity FROM player_ship_parts sp WHERE sp.user_id = _uid AND sp.item_id = _part_id) THEN
            DELETE FROM player_ship_parts
             WHERE user_id = _uid AND item_id = _part_id
               AND quantity = _part_count;
        ELSE
            UPDATE player_ship_parts
               SET quantity = quantity - _part_count
             WHERE user_id = _uid AND item_id = _part_id
               AND quantity >= _part_count;
        END IF;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Not enough part % (need %)', _part_id, _part_count;
        END IF;
    END LOOP;
```

---

### 3. `rpc_complete_dungeon_run` — double-complete race grants duplicate rewards

**File:** `supabase/rpc.sql`, line 479

The run is loaded with a plain `SELECT`. Two concurrent calls both see `status = 'in_progress'`, both grant full rewards, and both mark the run as completed. Credits and items are doubled.

**Replace line 479:**

```sql
    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid FOR UPDATE;
```

The `FOR UPDATE` lock makes the second transaction wait. After the first commits (`status = 'success'`), the second re-reads the committed row, sees `status <> 'in_progress'`, and the existing check on line 481 raises the exception cleanly.

Apply the same `FOR UPDATE` fix to the other dungeon RPCs that load the run:

**Line 383 (`rpc_submit_run_choice`):**
```sql
    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid FOR UPDATE;
```

**Line 425 (`rpc_submit_multiplier`):**
```sql
    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid FOR UPDATE;
```

---

### 4. `rpc_start_dungeon_run` — double-start race creates two active runs

**File:** `supabase/rpc.sql`, lines 330–332

The `IF EXISTS (… status = 'in_progress')` check and the `INSERT` are not atomic. Two concurrent calls both pass the check and both insert an active run.

**Replace lines 330–332 with a row-level lock on `player_state`:**

```sql
    -- serialize per-user dungeon starts
    PERFORM 1 FROM player_state WHERE user_id = _uid FOR UPDATE;

    IF EXISTS (SELECT 1 FROM dungeon_runs WHERE user_id = _uid AND status = 'in_progress') THEN
        RAISE EXCEPTION 'A dungeon run is already in progress';
    END IF;
```

Locking the `player_state` row serializes all dungeon start attempts for the same user.

---

## P1 — Incorrect game logic

### 5. `rpc_complete_dungeon_run` — combat XP over-distributed

**File:** `supabase/rpc.sql`, lines 588–589

`_total_skills` counts **distinct skill keys** instead of **total choice uses**. If a player submits 3 choices all using `attack`, the pool is divided by 1 (one distinct key) instead of 3 (total uses). Attack receives 3× the intended XP, exceeding the pool.

Verified:
```
skill_counts = {"attack":3, "defense":1}
BUGGY _total_skills = 2  → attack gets floor(pool * 3/2) = 150% of pool
FIXED _total_skills = 4  → attack gets floor(pool * 3/4) = 75% of pool
```

**Replace lines 588–589:**

```sql
    SELECT coalesce(sum((v)::int), 0)::int INTO _total_skills
      FROM jsonb_each_text(_skill_counts) AS x(k, v);
```

---

## P2 — Defensive hardening

### 6. All SECURITY DEFINER functions missing function-level `SET search_path`

**File:** `supabase/rpc.sql` — all 11 SECURITY DEFINER functions

The functions use `set_config('search_path', 'public', true)` inside the body, which works but is not the Supabase-recommended hardening. The function-level `SET search_path` clause is applied before the body runs and cannot be bypassed.

**Add `SET search_path = public` to each function definition.** Example for `rpc_bootstrap_player` (line 119–122):

```sql
CREATE OR REPLACE FUNCTION rpc_bootstrap_player()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
```

Apply to all 11 functions: `_build_player_snapshot`, `rpc_bootstrap_player`, `rpc_get_player_snapshot`, `rpc_claim_all`, `rpc_start_dungeon_run`, `rpc_submit_run_choice`, `rpc_submit_multiplier`, `rpc_complete_dungeon_run`, `rpc_equip_ship_part`, `rpc_apply_ship_upgrade`, `rpc_unlock_base_or_location`.

The existing `set_config` calls inside the bodies can remain for belt-and-suspenders safety.

---

### 7. `rpc_claim_all` — NULL skill level crashes on missing production_skills row

**File:** `supabase/rpc.sql`, lines 249–251

If a `production_skills` row is missing for a user (data corruption, manual deletion), `SELECT INTO` sets `_skill_level` to NULL. NULL propagates through the arithmetic, producing `_produced = NULL`. The `IF _produced <= 0` guard does **not** catch NULL (NULL is neither ≤ 0 nor > 0), so execution falls through to an `INSERT` with `quantity = NULL`, violating the `NOT NULL` constraint on `base_inventory.quantity`.

Verified: `IF NULL <= 0` evaluates to NULL (falsy), skipping the CONTINUE.

**Replace lines 249–251:**

```sql
                _skill_level := coalesce(
                    (SELECT sk.level FROM production_skills sk
                      WHERE sk.user_id = _uid AND sk.skill_id = _rule.skill_id),
                    1);
```
