-- ============================================================
-- rpc.sql — V1 SECURITY DEFINER RPC functions
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- CONSTANTS / HELPERS
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION _offline_cap_seconds() RETURNS int
LANGUAGE sql IMMUTABLE AS $$ SELECT 43200; $$;  -- 12 h

CREATE OR REPLACE FUNCTION _xp_for_next_level(p_level int) RETURNS bigint
LANGUAGE sql IMMUTABLE AS $$ SELECT (p_level * 1000)::bigint; $$;

CREATE OR REPLACE FUNCTION _default_cap_for_item(p_item_id text) RETURNS bigint
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_item_id = 'credits'       THEN 50000
        WHEN p_item_id = 'food_basic'    THEN 8000
        WHEN p_item_id = 'ore_iron'      THEN 5000
        WHEN p_item_id = 'ore_copper'    THEN 3000
        WHEN p_item_id = 'bio_samples'   THEN 2000
        WHEN p_item_id = 'circuit_basic' THEN 1500
        WHEN p_item_id = 'metal_iron'    THEN 1000
        WHEN p_item_id = 'metal_copper'  THEN  800
        ELSE 10000
    END::bigint;
$$;

CREATE OR REPLACE FUNCTION _pick_weighted_item(p_drops jsonb)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    _total   numeric := 0;
    _roll    numeric;
    _running numeric := 0;
    _drop    jsonb;
BEGIN
    SELECT coalesce(sum((d->>'weight')::numeric), 0)
      INTO _total
      FROM jsonb_array_elements(p_drops) d;
    IF _total <= 0 THEN RETURN NULL; END IF;
    _roll := random() * _total;
    FOR _drop IN SELECT d FROM jsonb_array_elements(p_drops) d LOOP
        _running := _running + (_drop->>'weight')::numeric;
        IF _roll < _running THEN RETURN _drop->>'item_id'; END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SHARED: build full player snapshot
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION _build_player_snapshot(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _result jsonb;
BEGIN
    PERFORM set_config('search_path', 'public', true);

    SELECT jsonb_build_object(
        'player_state',
            coalesce((
                SELECT to_jsonb(ps) || jsonb_build_object('display_name', p.display_name)
                  FROM player_state ps
                  JOIN profiles p ON p.user_id = ps.user_id
                 WHERE ps.user_id = p_uid
            ), '{}'::jsonb),
        'bases',
            coalesce((
                SELECT jsonb_agg(to_jsonb(pb) ORDER BY pb.unlocked_at)
                  FROM player_bases pb WHERE pb.user_id = p_uid
            ), '[]'::jsonb),
        'inventories',
            coalesce((
                SELECT jsonb_agg(to_jsonb(bi))
                  FROM base_inventory bi WHERE bi.user_id = p_uid
            ), '[]'::jsonb),
        'caps',
            coalesce((
                SELECT jsonb_agg(to_jsonb(sc))
                  FROM base_storage_caps sc WHERE sc.user_id = p_uid
            ), '[]'::jsonb),
        'production_skills',
            coalesce((SELECT jsonb_agg(to_jsonb(sk) ORDER BY sk.skill_id)
              FROM production_skills sk WHERE sk.user_id = p_uid), '[]'::jsonb),
        'combat_skills',
            coalesce((SELECT jsonb_agg(to_jsonb(ck) ORDER BY ck.skill_id)
              FROM combat_skills ck WHERE ck.user_id = p_uid), '[]'::jsonb),
        'ship', jsonb_build_object(
            'info', coalesce((SELECT to_jsonb(sh) FROM player_ship sh WHERE sh.user_id = p_uid), '{}'::jsonb),
            'parts', coalesce((SELECT jsonb_agg(to_jsonb(sp))
              FROM player_ship_parts sp WHERE sp.user_id = p_uid), '[]'::jsonb),
            'equipped', coalesce((SELECT jsonb_agg(to_jsonb(se))
              FROM player_ship_equipped se WHERE se.user_id = p_uid), '[]'::jsonb),
            'upgrades', coalesce((SELECT jsonb_agg(to_jsonb(su))
              FROM player_ship_upgrades su WHERE su.user_id = p_uid), '[]'::jsonb)
        ),
        'unlocks',
            coalesce((SELECT jsonb_agg(to_jsonb(u))
              FROM player_unlocks u WHERE u.user_id = p_uid), '[]'::jsonb),
        'active_run',
            coalesce((
                SELECT to_jsonb(dr)
                  FROM dungeon_runs dr
                 WHERE dr.user_id = p_uid AND dr.status = 'in_progress'
                 LIMIT 1
            ), '{}'::jsonb)
    ) INTO _result;

    RETURN _result;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 1) rpc_bootstrap_player
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_bootstrap_player()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _uid     uuid := auth.uid();
    _base_id uuid;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- core rows
    INSERT INTO profiles (user_id) VALUES (_uid) ON CONFLICT DO NOTHING;
    INSERT INTO player_state (user_id) VALUES (_uid) ON CONFLICT DO NOTHING;
    INSERT INTO player_ship  (user_id) VALUES (_uid) ON CONFLICT DO NOTHING;

    -- earth base
    INSERT INTO player_bases (user_id, base_type_id)
        VALUES (_uid, 'earth')
        ON CONFLICT (user_id, base_type_id) DO NOTHING
        RETURNING id INTO _base_id;

    IF _base_id IS NULL THEN
        SELECT id INTO _base_id
          FROM player_bases
         WHERE user_id = _uid AND base_type_id = 'earth';
    END IF;

    -- production skills
    INSERT INTO production_skills (user_id, skill_id)
        VALUES (_uid,'mining'),(_uid,'farming'),(_uid,'ranching'),
               (_uid,'refining'),(_uid,'crafting'),(_uid,'tech')
        ON CONFLICT DO NOTHING;

    -- combat skills
    INSERT INTO combat_skills (user_id, skill_id)
        VALUES (_uid,'attack'),(_uid,'defense'),(_uid,'health')
        ON CONFLICT DO NOTHING;

    -- default storage caps for earth
    INSERT INTO base_storage_caps (user_id, base_id, item_id, cap)
        SELECT _uid, _base_id, ipr.item_id, _default_cap_for_item(ipr.item_id)
          FROM idle_production_rules ipr
         WHERE ipr.base_type_id = 'earth'
        ON CONFLICT (base_id, item_id) DO NOTHING;

    -- seed starting inventory (100 credits on earth)
    INSERT INTO base_inventory (user_id, base_id, item_id, quantity)
        VALUES (_uid, _base_id, 'credits', 100)
        ON CONFLICT (base_id, item_id) DO NOTHING;

    -- starting unlocks
    INSERT INTO player_unlocks (user_id, unlock_type, unlock_key)
        VALUES (_uid, 'base', 'earth'), (_uid, 'location', 'earth')
        ON CONFLICT DO NOTHING;

    RETURN _build_player_snapshot(_uid);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 2) rpc_get_player_snapshot
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_get_player_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _uid uuid := auth.uid();
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = _uid) THEN
        RAISE EXCEPTION 'Player not bootstrapped';
    END IF;

    RETURN _build_player_snapshot(_uid);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 3) rpc_claim_all
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_claim_all(p_base_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid           uuid := auth.uid();
    _now           timestamptz := now();
    _base          record;
    _rule          record;
    _elapsed       numeric;
    _skill_level   int;
    _effective_rate numeric;
    _produced      bigint;
    _cap           bigint;
    _current_qty   bigint;
    _base_deltas   jsonb;
    _base_inv      jsonb;
    _all_bases     jsonb := '[]'::jsonb;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    FOR _base IN
        SELECT pb.*
          FROM player_bases pb
         WHERE pb.user_id = _uid
           AND (p_base_type IS NULL OR pb.base_type_id = p_base_type)
    LOOP
        _elapsed := EXTRACT(EPOCH FROM (_now - _base.last_claim_at));
        _elapsed := LEAST(GREATEST(_elapsed, 0), _offline_cap_seconds());

        _base_deltas := '{}'::jsonb;

        IF _elapsed > 0 THEN
            FOR _rule IN
                SELECT ipr.*
                  FROM idle_production_rules ipr
                 WHERE ipr.base_type_id = _base.base_type_id
            LOOP
                SELECT coalesce(sk.level, 1) INTO _skill_level
                  FROM production_skills sk
                 WHERE sk.user_id = _uid AND sk.skill_id = _rule.skill_id;

                _effective_rate := _rule.rate_per_second
                    * (1.0 + (_skill_level - 1) * _rule.skill_bonus_pct / 100.0);
                _produced := floor(_effective_rate * _elapsed)::bigint;

                IF _produced <= 0 THEN CONTINUE; END IF;

                -- apply cap
                SELECT sc.cap INTO _cap
                  FROM base_storage_caps sc
                 WHERE sc.base_id = _base.id AND sc.item_id = _rule.item_id;

                IF _cap IS NOT NULL THEN
                    SELECT coalesce(bi.quantity, 0) INTO _current_qty
                      FROM base_inventory bi
                     WHERE bi.base_id = _base.id AND bi.item_id = _rule.item_id;
                    _current_qty := coalesce(_current_qty, 0);
                    _produced := LEAST(_produced, GREATEST(_cap - _current_qty, 0));
                END IF;

                IF _produced <= 0 THEN CONTINUE; END IF;

                -- upsert inventory
                INSERT INTO base_inventory (user_id, base_id, item_id, quantity, updated_at)
                    VALUES (_uid, _base.id, _rule.item_id, _produced, _now)
                    ON CONFLICT (base_id, item_id)
                    DO UPDATE SET quantity  = base_inventory.quantity + EXCLUDED.quantity,
                                  updated_at = _now;

                -- ledger
                INSERT INTO resource_ledger (user_id, base_id, item_id, delta, reason)
                    VALUES (_uid, _base.id, _rule.item_id, _produced, 'idle_claim');

                _base_deltas := _base_deltas || jsonb_build_object(_rule.item_id, _produced);
            END LOOP;

            UPDATE player_bases SET last_claim_at = _now WHERE id = _base.id;
        END IF;

        -- current inventory after claim
        SELECT coalesce(jsonb_object_agg(bi.item_id, bi.quantity), '{}'::jsonb)
          INTO _base_inv
          FROM base_inventory bi WHERE bi.base_id = _base.id;

        _all_bases := _all_bases || jsonb_build_array(jsonb_build_object(
            'base_id',         _base.id,
            'base_type_id',    _base.base_type_id,
            'elapsed_seconds', round(_elapsed),
            'deltas',          _base_deltas,
            'inventory',       _base_inv
        ));
    END LOOP;

    UPDATE player_state SET last_claim_at = _now, updated_at = _now WHERE user_id = _uid;

    RETURN jsonb_build_object('claimed_at', _now, 'bases', _all_bases);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4a) rpc_start_dungeon_run
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_start_dungeon_run(p_tier int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid    uuid := auth.uid();
    _highest int;
    _run_id  uuid;
    _tier_row record;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- no concurrent runs
    IF EXISTS (SELECT 1 FROM dungeon_runs WHERE user_id = _uid AND status = 'in_progress') THEN
        RAISE EXCEPTION 'A dungeon run is already in progress';
    END IF;

    SELECT highest_dungeon_tier INTO _highest FROM player_state WHERE user_id = _uid;
    IF _highest IS NULL THEN RAISE EXCEPTION 'Player not bootstrapped'; END IF;

    IF p_tier < 1 OR p_tier > 25 THEN RAISE EXCEPTION 'Invalid tier'; END IF;
    IF p_tier > _highest + 1 THEN RAISE EXCEPTION 'Tier not unlocked'; END IF;

    SELECT * INTO _tier_row FROM dungeon_tiers WHERE tier = p_tier;

    INSERT INTO dungeon_runs (user_id, tier)
        VALUES (_uid, p_tier)
        RETURNING id INTO _run_id;

    UPDATE player_state
       SET total_dungeon_runs = total_dungeon_runs + 1, updated_at = now()
     WHERE user_id = _uid;

    RETURN jsonb_build_object(
        'run_id',           _run_id,
        'tier',             p_tier,
        'tier_name',        _tier_row.name,
        'duration_seconds', _tier_row.duration_seconds,
        'enemy_power',      _tier_row.enemy_power
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4b) rpc_submit_run_choice
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_submit_run_choice(
    p_run_id     uuid,
    p_choice_key text,
    p_skills_used jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid        uuid := auth.uid();
    _run        record;
    _next_step  int;
    _skill      text;
    _choice_id  uuid;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid;
    IF _run IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
    IF _run.status <> 'in_progress' THEN RAISE EXCEPTION 'Run is not in progress'; END IF;

    SELECT coalesce(max(step), 0) + 1 INTO _next_step
      FROM dungeon_run_choices WHERE run_id = p_run_id;

    _skill := p_skills_used->>0;  -- primary skill

    INSERT INTO dungeon_run_choices (run_id, user_id, step, choice_key, skill_used)
        VALUES (p_run_id, _uid, _next_step, p_choice_key, _skill)
        RETURNING id INTO _choice_id;

    RETURN jsonb_build_object(
        'choice_id', _choice_id,
        'run_id',    p_run_id,
        'step',      _next_step,
        'skill_used', _skill
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4c) rpc_submit_multiplier
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_submit_multiplier(
    p_run_id     uuid,
    p_multiplier numeric,
    p_source     text DEFAULT 'skill_check'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid uuid := auth.uid();
    _run record;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid;
    IF _run IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
    IF _run.status <> 'in_progress' THEN RAISE EXCEPTION 'Run is not in progress'; END IF;
    IF p_multiplier < 1.0 OR p_multiplier > 3.0 THEN RAISE EXCEPTION 'Multiplier out of range'; END IF;

    UPDATE dungeon_runs SET multiplier = p_multiplier WHERE id = p_run_id;

    RETURN jsonb_build_object(
        'run_id',     p_run_id,
        'multiplier', p_multiplier,
        'source',     p_source
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4d) rpc_complete_dungeon_run
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_complete_dungeon_run(
    p_run_id  uuid,
    p_outcome text  -- 'success' | 'failure'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid            uuid := auth.uid();
    _run            record;
    _tier_row       record;
    _outcome_factor numeric;
    _credit_reward  bigint;
    _xp_pool        bigint;
    _base_id        uuid;
    _rewards        jsonb := '[]'::jsonb;
    _new_levels     jsonb := '[]'::jsonb;
    _new_unlocks    jsonb := '[]'::jsonb;
    _item_id        text;
    _qty            bigint;
    _drop_table     jsonb;
    _picked         text;
    _skill_counts   jsonb;
    _sk             record;
    _skill_xp       bigint;
    _old_level      int;
    _new_xp         bigint;
    _new_level      int;
    _total_skills   int;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    IF p_outcome NOT IN ('success','failure') THEN RAISE EXCEPTION 'Invalid outcome'; END IF;

    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid;
    IF _run IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
    IF _run.status <> 'in_progress' THEN RAISE EXCEPTION 'Run is not in progress'; END IF;

    SELECT * INTO _tier_row FROM dungeon_tiers WHERE tier = _run.tier;

    -- earth base receives item rewards
    SELECT id INTO _base_id FROM player_bases WHERE user_id = _uid AND base_type_id = 'earth';

    _outcome_factor := CASE WHEN p_outcome = 'success' THEN 1.0 ELSE 0.5 END;

    -- ── credit reward ───────────────────────────────────────
    _credit_reward := floor(_tier_row.base_reward_credits * _run.multiplier * _outcome_factor)::bigint;
    IF _credit_reward > 0 THEN
        INSERT INTO base_inventory (user_id, base_id, item_id, quantity, updated_at)
            VALUES (_uid, _base_id, 'credits', _credit_reward, now())
            ON CONFLICT (base_id, item_id)
            DO UPDATE SET quantity = base_inventory.quantity + EXCLUDED.quantity, updated_at = now();
        INSERT INTO dungeon_run_rewards (run_id, user_id, item_id, quantity)
            VALUES (p_run_id, _uid, 'credits', _credit_reward);
        INSERT INTO resource_ledger (user_id, base_id, item_id, delta, reason, ref_id)
            VALUES (_uid, _base_id, 'credits', _credit_reward, 'dungeon_reward', p_run_id);
        _rewards := _rewards || jsonb_build_array(jsonb_build_object('item_id','credits','quantity',_credit_reward));
    END IF;

    -- ── resource drops (deterministic by tier) ──────────────
    FOR _item_id, _qty IN
        SELECT v.item_id, greatest(floor(v.base_qty * _run.multiplier * _outcome_factor)::bigint, 1)
          FROM (VALUES
            ('ore_iron',      (_run.tier * 5)::bigint),
            ('ore_copper',    (_run.tier * 3)::bigint),
            ('food_basic',    (_run.tier * 4)::bigint)
          ) v(item_id, base_qty)
    LOOP
        INSERT INTO base_inventory (user_id, base_id, item_id, quantity, updated_at)
            VALUES (_uid, _base_id, _item_id, _qty, now())
            ON CONFLICT (base_id, item_id)
            DO UPDATE SET quantity = base_inventory.quantity + EXCLUDED.quantity, updated_at = now();
        INSERT INTO dungeon_run_rewards (run_id, user_id, item_id, quantity)
            VALUES (p_run_id, _uid, _item_id, _qty);
        INSERT INTO resource_ledger (user_id, base_id, item_id, delta, reason, ref_id)
            VALUES (_uid, _base_id, _item_id, _qty, 'dungeon_reward', p_run_id);
        _rewards := _rewards || jsonb_build_array(jsonb_build_object('item_id', _item_id, 'quantity', _qty));
    END LOOP;

    -- ── rare drop (weighted pick) ───────────────────────────
    _drop_table := '[]'::jsonb;
    IF _run.tier >= 3  THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','crystal_prism',     'weight', least(_run.tier * 4, 80))); END IF;
    IF _run.tier >= 5  THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','quantum_dust',      'weight', least(_run.tier * 3, 60))); END IF;
    IF _run.tier >= 7  THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','void_essence',      'weight', least(_run.tier * 2, 40))); END IF;
    IF _run.tier >= 10 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','dark_matter_shard', 'weight', least(_run.tier, 25)));     END IF;
    IF _run.tier >= 15 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','alien_artifact',    'weight', least(_run.tier - 5, 15))); END IF;
    IF _run.tier >= 20 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','nova_fragment',     'weight', _run.tier - 15));           END IF;

    -- add a "nothing" weight so drops aren't guaranteed
    _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','__none__','weight', 200));

    _picked := _pick_weighted_item(_drop_table);
    IF _picked IS NOT NULL AND _picked <> '__none__' THEN
        INSERT INTO base_inventory (user_id, base_id, item_id, quantity, updated_at)
            VALUES (_uid, _base_id, _picked, 1, now())
            ON CONFLICT (base_id, item_id)
            DO UPDATE SET quantity = base_inventory.quantity + 1, updated_at = now();
        INSERT INTO dungeon_run_rewards (run_id, user_id, item_id, quantity)
            VALUES (p_run_id, _uid, _picked, 1);
        INSERT INTO resource_ledger (user_id, base_id, item_id, delta, reason, ref_id)
            VALUES (_uid, _base_id, _picked, 1, 'dungeon_drop', p_run_id);
        _rewards := _rewards || jsonb_build_array(jsonb_build_object('item_id', _picked, 'quantity', 1));
    END IF;

    -- ── ship part drop (weighted pick, tier 5+) ─────────────
    IF _run.tier >= 5 THEN
        _drop_table := jsonb_build_array(
            jsonb_build_object('item_id','__none__','weight', 300));
        _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_hull_plate', 'weight', least(_run.tier * 3, 50)));
        _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_thruster',   'weight', least(_run.tier * 2, 40)));
        IF _run.tier >= 8  THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_engine_mk1', 'weight', least(_run.tier * 2, 30))); END IF;
        IF _run.tier >= 8  THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_shield_mk1', 'weight', least(_run.tier * 2, 30))); END IF;
        IF _run.tier >= 10 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_nav_mk1',    'weight', least(_run.tier, 20)));     END IF;
        IF _run.tier >= 15 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_engine_mk2', 'weight', least(_run.tier - 10, 10))); END IF;
        IF _run.tier >= 15 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_shield_mk2', 'weight', least(_run.tier - 10, 10))); END IF;
        IF _run.tier >= 18 THEN _drop_table := _drop_table || jsonb_build_array(jsonb_build_object('item_id','ship_nav_mk2',    'weight', least(_run.tier - 14, 8)));  END IF;

        _picked := _pick_weighted_item(_drop_table);
        IF _picked IS NOT NULL AND _picked <> '__none__' THEN
            INSERT INTO player_ship_parts (user_id, item_id, quantity)
                VALUES (_uid, _picked, 1)
                ON CONFLICT (user_id, item_id)
                DO UPDATE SET quantity = player_ship_parts.quantity + 1;
            INSERT INTO dungeon_run_rewards (run_id, user_id, item_id, quantity)
                VALUES (p_run_id, _uid, _picked, 1);
            _rewards := _rewards || jsonb_build_array(jsonb_build_object('item_id', _picked, 'quantity', 1, 'type', 'ship_part'));
        END IF;
    END IF;

    -- ── combat XP distribution ──────────────────────────────
    _xp_pool := floor(_tier_row.base_reward_xp * _run.multiplier * _outcome_factor)::bigint;

    -- count how many times each combat skill was used in choices
    SELECT coalesce(jsonb_object_agg(skill_used, cnt), '{}'::jsonb)
      INTO _skill_counts
      FROM (
          SELECT c.skill_used, count(*)::int AS cnt
            FROM dungeon_run_choices c
           WHERE c.run_id = p_run_id
             AND c.skill_used IN ('attack','defense','health')
           GROUP BY c.skill_used
      ) sub;

    SELECT count(*)::int INTO _total_skills
      FROM jsonb_each(_skill_counts);

    -- if no combat skills were used in choices, split evenly
    IF _total_skills = 0 THEN
        _skill_counts := '{"attack":1,"defense":1,"health":1}'::jsonb;
        _total_skills := 3;
    END IF;

    FOR _sk IN
        SELECT cs.id, cs.skill_id, cs.level, cs.xp
          FROM combat_skills cs
         WHERE cs.user_id = _uid
           AND cs.skill_id IN (SELECT k FROM jsonb_object_keys(_skill_counts) k)
    LOOP
        _skill_xp := floor(_xp_pool * coalesce((_skill_counts->>_sk.skill_id)::numeric, 0) / _total_skills)::bigint;
        IF _skill_xp <= 0 THEN CONTINUE; END IF;

        _new_xp    := _sk.xp + _skill_xp;
        _new_level := _sk.level;
        _old_level := _sk.level;

        WHILE _new_xp >= _xp_for_next_level(_new_level) LOOP
            _new_xp    := _new_xp - _xp_for_next_level(_new_level);
            _new_level := _new_level + 1;
        END LOOP;

        UPDATE combat_skills
           SET xp = _new_xp, level = _new_level, updated_at = now()
         WHERE id = _sk.id;

        -- record XP on the choices that used this skill
        UPDATE dungeon_run_choices
           SET xp_awarded = floor(_skill_xp::numeric /
               greatest((_skill_counts->>_sk.skill_id)::int, 1))::bigint
         WHERE run_id = p_run_id AND skill_used = _sk.skill_id;

        IF _new_level > _old_level THEN
            _new_levels := _new_levels || jsonb_build_array(jsonb_build_object(
                'skill_id', _sk.skill_id,
                'old_level', _old_level,
                'new_level', _new_level,
                'xp', _new_xp
            ));
        END IF;
    END LOOP;

    -- also grant production XP for production skills used in choices
    FOR _sk IN
        SELECT ps.id, ps.skill_id, ps.level, ps.xp
          FROM production_skills ps
         WHERE ps.user_id = _uid
           AND ps.skill_id IN (
               SELECT DISTINCT c.skill_used FROM dungeon_run_choices c
                WHERE c.run_id = p_run_id
                  AND c.skill_used IN ('mining','farming','ranching','refining','crafting','tech')
           )
    LOOP
        _skill_xp := floor(_xp_pool::numeric * 0.5 /
            greatest((SELECT count(DISTINCT skill_used) FROM dungeon_run_choices
                       WHERE run_id = p_run_id
                         AND skill_used IN ('mining','farming','ranching','refining','crafting','tech')), 1)
        )::bigint;
        IF _skill_xp <= 0 THEN CONTINUE; END IF;

        _new_xp    := _sk.xp + _skill_xp;
        _new_level := _sk.level;
        _old_level := _sk.level;

        WHILE _new_xp >= _xp_for_next_level(_new_level) LOOP
            _new_xp    := _new_xp - _xp_for_next_level(_new_level);
            _new_level := _new_level + 1;
        END LOOP;

        UPDATE production_skills
           SET xp = _new_xp, level = _new_level, updated_at = now()
         WHERE id = _sk.id;

        IF _new_level > _old_level THEN
            _new_levels := _new_levels || jsonb_build_array(jsonb_build_object(
                'skill_id', _sk.skill_id,
                'old_level', _old_level,
                'new_level', _new_level,
                'xp', _new_xp
            ));
        END IF;
    END LOOP;

    -- ── ladder unlock on success ────────────────────────────
    IF p_outcome = 'success' AND _run.tier > (SELECT highest_dungeon_tier FROM player_state WHERE user_id = _uid) THEN
        UPDATE player_state
           SET highest_dungeon_tier = _run.tier, updated_at = now()
         WHERE user_id = _uid;

        _new_unlocks := _new_unlocks || jsonb_build_array(jsonb_build_object(
            'type', 'dungeon_tier',
            'tier', _run.tier
        ));
    END IF;

    -- ── mark run complete ───────────────────────────────────
    UPDATE dungeon_runs
       SET status = p_outcome, completed_at = now()
     WHERE id = p_run_id;

    RETURN jsonb_build_object(
        'run_id',      p_run_id,
        'outcome',     p_outcome,
        'multiplier',  _run.multiplier,
        'rewards',     _rewards,
        'level_ups',   _new_levels,
        'new_unlocks', _new_unlocks
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5a) rpc_equip_ship_part
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_equip_ship_part(p_slot text, p_part_item_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid uuid := auth.uid();
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- verify item is a ship_part
    IF NOT EXISTS (SELECT 1 FROM items WHERE id = p_part_item_id AND category = 'ship_part') THEN
        RAISE EXCEPTION 'Item is not a ship part';
    END IF;

    -- verify ownership
    IF NOT EXISTS (SELECT 1 FROM player_ship_parts WHERE user_id = _uid AND item_id = p_part_item_id) THEN
        RAISE EXCEPTION 'You do not own this ship part';
    END IF;

    -- equip (upsert into slot)
    INSERT INTO player_ship_equipped (user_id, slot, item_id)
        VALUES (_uid, p_slot, p_part_item_id)
        ON CONFLICT (user_id, slot)
        DO UPDATE SET item_id = EXCLUDED.item_id, equipped_at = now();

    RETURN jsonb_build_object(
        'slot',    p_slot,
        'item_id', p_part_item_id,
        'equipped', (SELECT jsonb_agg(to_jsonb(se))
                       FROM player_ship_equipped se WHERE se.user_id = _uid)
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5b) rpc_apply_ship_upgrade
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_apply_ship_upgrade(p_upgrade_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid           uuid := auth.uid();
    _def           record;
    _current_level int;
    _max_level     int;
    _level_data    jsonb;
    _cost_credits  bigint;
    _parts_needed  jsonb;
    _part_id       text;
    _part_count    int;
    _owned_qty     int;
    _base_id       uuid;
    _current_cred  bigint;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT * INTO _def FROM ship_upgrade_defs WHERE id = p_upgrade_id;
    IF _def IS NULL THEN RAISE EXCEPTION 'Upgrade not found'; END IF;

    -- current level = number of times this upgrade has been applied (via ledger)
    SELECT count(*)::int INTO _current_level
      FROM resource_ledger
     WHERE user_id = _uid AND reason = 'ship_upgrade:' || p_upgrade_id;

    _max_level := (_def.effect->>'max_level')::int;
    IF _current_level >= _max_level THEN RAISE EXCEPTION 'Already at max level'; END IF;

    -- get next-level cost data
    _level_data := _def.effect->'levels'->_current_level;  -- 0-indexed
    IF _level_data IS NULL THEN RAISE EXCEPTION 'Level data missing'; END IF;

    _cost_credits := (_level_data->>'credits')::bigint;
    _parts_needed := _level_data->'parts';

    -- earth base for credit deductions
    SELECT id INTO _base_id FROM player_bases WHERE user_id = _uid AND base_type_id = 'earth';
    IF _base_id IS NULL THEN RAISE EXCEPTION 'No earth base found'; END IF;

    -- check + deduct credits
    SELECT coalesce(bi.quantity, 0) INTO _current_cred
      FROM base_inventory bi
     WHERE bi.base_id = _base_id AND bi.item_id = 'credits';

    IF coalesce(_current_cred, 0) < _cost_credits THEN
        RAISE EXCEPTION 'Not enough credits (need %, have %)', _cost_credits, coalesce(_current_cred, 0);
    END IF;

    UPDATE base_inventory
       SET quantity = quantity - _cost_credits, updated_at = now()
     WHERE base_id = _base_id AND item_id = 'credits';

    -- check + deduct ship parts
    FOR _part_id, _part_count IN
        SELECT p.value::text, count(*)::int
          FROM jsonb_array_elements_text(_parts_needed) p(value)
         GROUP BY p.value
    LOOP
        SELECT coalesce(sp.quantity, 0) INTO _owned_qty
          FROM player_ship_parts sp
         WHERE sp.user_id = _uid AND sp.item_id = _part_id;

        IF coalesce(_owned_qty, 0) < _part_count THEN
            RAISE EXCEPTION 'Not enough part % (need %, have %)', _part_id, _part_count, coalesce(_owned_qty, 0);
        END IF;

        IF _owned_qty - _part_count > 0 THEN
            UPDATE player_ship_parts
               SET quantity = quantity - _part_count
             WHERE user_id = _uid AND item_id = _part_id;
        ELSE
            DELETE FROM player_ship_parts WHERE user_id = _uid AND item_id = _part_id;
        END IF;
    END LOOP;

    -- record upgrade application
    INSERT INTO player_ship_upgrades (user_id, upgrade_def_id)
        VALUES (_uid, p_upgrade_id)
        ON CONFLICT (user_id, upgrade_def_id)
        DO UPDATE SET applied_at = now();

    -- ledger entry (for level tracking)
    INSERT INTO resource_ledger (user_id, base_id, item_id, delta, reason)
        VALUES (_uid, _base_id, 'credits', -_cost_credits, 'ship_upgrade:' || p_upgrade_id);

    RETURN jsonb_build_object(
        'upgrade_id',    p_upgrade_id,
        'new_level',     _current_level + 1,
        'max_level',     _max_level,
        'credits_spent', _cost_credits,
        'parts_spent',   _parts_needed
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5c) rpc_unlock_base_or_location
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_unlock_base_or_location(
    p_unlock_type text,
    p_unlock_key  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    _uid       uuid := auth.uid();
    _nav_level int;
    _base_id   uuid;
    _bt        record;
    _required  text;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    IF p_unlock_type NOT IN ('base','location','feature') THEN
        RAISE EXCEPTION 'Invalid unlock_type';
    END IF;

    -- already unlocked?
    IF EXISTS (
        SELECT 1 FROM player_unlocks
         WHERE user_id = _uid AND unlock_type = p_unlock_type AND unlock_key = p_unlock_key
    ) THEN
        RAISE EXCEPTION 'Already unlocked';
    END IF;

    -- for base / location unlocks, verify nav_computer level
    IF p_unlock_type IN ('base','location') THEN
        SELECT * INTO _bt FROM base_types WHERE id = p_unlock_key;
        IF _bt IS NULL THEN RAISE EXCEPTION 'Unknown base/location key'; END IF;

        -- determine player's nav_computer upgrade level
        SELECT count(*)::int INTO _nav_level
          FROM resource_ledger
         WHERE user_id = _uid AND reason = 'ship_upgrade:nav_computer';

        -- check nav_computer levels for an "unlocks" entry matching p_unlock_key
        _required := NULL;
        SELECT (lv->>'level')::text INTO _required
          FROM ship_upgrade_defs sud,
               jsonb_array_elements(sud.effect->'levels') lv
         WHERE sud.id = 'nav_computer'
           AND lv->>'unlocks' = p_unlock_key
         ORDER BY (lv->>'level')::int
         LIMIT 1;

        IF _required IS NOT NULL AND _nav_level < (_required::int) THEN
            RAISE EXCEPTION 'Requires nav_computer level % (current: %)', _required, _nav_level;
        END IF;
    END IF;

    -- insert unlock
    INSERT INTO player_unlocks (user_id, unlock_type, unlock_key)
        VALUES (_uid, p_unlock_type, p_unlock_key);

    -- if unlocking a base, also create the player_base + default caps
    IF p_unlock_type = 'base' AND EXISTS (SELECT 1 FROM base_types WHERE id = p_unlock_key) THEN
        INSERT INTO player_bases (user_id, base_type_id)
            VALUES (_uid, p_unlock_key)
            ON CONFLICT (user_id, base_type_id) DO NOTHING
            RETURNING id INTO _base_id;

        IF _base_id IS NOT NULL THEN
            INSERT INTO base_storage_caps (user_id, base_id, item_id, cap)
                SELECT _uid, _base_id, ipr.item_id, _default_cap_for_item(ipr.item_id)
                  FROM idle_production_rules ipr
                 WHERE ipr.base_type_id = p_unlock_key
                ON CONFLICT (base_id, item_id) DO NOTHING;

            INSERT INTO base_inventory (user_id, base_id, item_id, quantity)
                VALUES (_uid, _base_id, 'credits', 0)
                ON CONFLICT (base_id, item_id) DO NOTHING;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'unlock_type', p_unlock_type,
        'unlock_key',  p_unlock_key,
        'unlocked',    true
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4e) rpc_abandon_dungeon_run
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_abandon_dungeon_run(p_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _uid uuid := auth.uid();
    _run record;
BEGIN
    PERFORM set_config('search_path', 'public', true);
    IF _uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT * INTO _run FROM dungeon_runs WHERE id = p_run_id AND user_id = _uid FOR UPDATE;
    IF _run IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
    IF _run.status <> 'in_progress' THEN RAISE EXCEPTION 'Run is not in progress'; END IF;

    UPDATE dungeon_runs
       SET status = 'abandoned', completed_at = now()
     WHERE id = p_run_id;

    RETURN jsonb_build_object(
        'run_id', p_run_id,
        'status', 'abandoned'
    );
END;
$$;
