-- ============================================================
-- schema.sql — V1 game backend (Supabase / Postgres 17)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- STATIC / CONTENT TABLES
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.base_types (
    id              text        PRIMARY KEY,
    name            text        NOT NULL,
    sort_order      int         NOT NULL DEFAULT 0,
    unlock_requirement text,
    available_in_v1 boolean     NOT NULL DEFAULT true
);

CREATE TABLE public.items (
    id          text    PRIMARY KEY,
    name        text    NOT NULL,
    category    text    NOT NULL CHECK (category IN (
                            'currency','resource','ship_part','consumable','misc'
                        )),
    rarity      text    NOT NULL DEFAULT 'common' CHECK (rarity IN (
                            'common','uncommon','rare','epic','legendary'
                        )),
    stackable   boolean NOT NULL DEFAULT true,
    description text
);

CREATE TABLE public.dungeon_tiers (
    tier                    int     PRIMARY KEY CHECK (tier BETWEEN 1 AND 25),
    name                    text    NOT NULL,
    min_combat_power        int     NOT NULL DEFAULT 0 CHECK (min_combat_power >= 0),
    base_reward_credits     bigint  NOT NULL CHECK (base_reward_credits >= 0),
    base_reward_xp          bigint  NOT NULL CHECK (base_reward_xp >= 0),
    duration_seconds        int     NOT NULL CHECK (duration_seconds BETWEEN 120 AND 300),
    enemy_power             int     NOT NULL CHECK (enemy_power > 0)
);

CREATE TABLE public.idle_production_rules (
    id              uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
    base_type_id    text    NOT NULL REFERENCES public.base_types(id),
    item_id         text    NOT NULL REFERENCES public.items(id),
    rate_per_second numeric NOT NULL CHECK (rate_per_second > 0),
    skill_id        text    NOT NULL,
    skill_bonus_pct numeric NOT NULL DEFAULT 0 CHECK (skill_bonus_pct >= 0),
    UNIQUE (base_type_id, item_id)
);

CREATE TABLE public.ship_upgrade_defs (
    id              text    PRIMARY KEY,
    name            text    NOT NULL,
    description     text,
    required_parts  jsonb   NOT NULL DEFAULT '[]'::jsonb,
    required_credits bigint NOT NULL DEFAULT 0 CHECK (required_credits >= 0),
    effect          jsonb   NOT NULL DEFAULT '{}'::jsonb,
    sort_order      int     NOT NULL DEFAULT 0
);

-- ────────────────────────────────────────────────────────────
-- PLAYER-OWNED TABLES
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.profiles (
    user_id      uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text        NOT NULL DEFAULT 'Space Cadet',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.player_state (
    user_id              uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    highest_dungeon_tier int         NOT NULL DEFAULT 0 CHECK (highest_dungeon_tier >= 0),
    last_login_at        timestamptz NOT NULL DEFAULT now(),
    last_claim_at        timestamptz NOT NULL DEFAULT now(),
    total_dungeon_runs   int         NOT NULL DEFAULT 0 CHECK (total_dungeon_runs >= 0),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.player_bases (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    base_type_id  text        NOT NULL REFERENCES public.base_types(id),
    unlocked_at   timestamptz NOT NULL DEFAULT now(),
    last_claim_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, base_type_id)
);

CREATE TABLE public.base_inventory (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    base_id    uuid        NOT NULL REFERENCES public.player_bases(id) ON DELETE CASCADE,
    item_id    text        NOT NULL REFERENCES public.items(id),
    quantity   bigint      NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (base_id, item_id)
);

CREATE TABLE public.base_storage_caps (
    id      uuid   PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid   NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    base_id uuid   NOT NULL REFERENCES public.player_bases(id) ON DELETE CASCADE,
    item_id text   NOT NULL REFERENCES public.items(id),
    cap     bigint NOT NULL CHECK (cap > 0),
    UNIQUE (base_id, item_id)
);

CREATE TABLE public.production_skills (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    skill_id   text        NOT NULL CHECK (skill_id IN (
                               'mining','farming','ranching','refining','crafting','tech'
                           )),
    level      int         NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp         bigint      NOT NULL DEFAULT 0 CHECK (xp >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, skill_id)
);

CREATE TABLE public.combat_skills (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    skill_id   text        NOT NULL CHECK (skill_id IN ('attack','defense','health')),
    level      int         NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp         bigint      NOT NULL DEFAULT 0 CHECK (xp >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, skill_id)
);

-- ── Ship ────────────────────────────────────────────────────

CREATE TABLE public.player_ship (
    user_id    uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    ship_name  text        NOT NULL DEFAULT 'Starter Ship',
    hull_level int         NOT NULL DEFAULT 1 CHECK (hull_level >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.player_ship_parts (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    item_id     text        NOT NULL REFERENCES public.items(id),
    quantity    int         NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    acquired_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, item_id)
);

CREATE TABLE public.player_ship_equipped (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    slot        text        NOT NULL,
    item_id     text        NOT NULL REFERENCES public.items(id),
    equipped_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, slot)
);

CREATE TABLE public.player_ship_upgrades (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    upgrade_def_id text        NOT NULL REFERENCES public.ship_upgrade_defs(id),
    applied_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, upgrade_def_id)
);

-- ── Unlocks ─────────────────────────────────────────────────

CREATE TABLE public.player_unlocks (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    unlock_type text        NOT NULL CHECK (unlock_type IN ('base','location','feature')),
    unlock_key  text        NOT NULL,
    unlocked_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, unlock_type, unlock_key)
);

-- ── Dungeons ────────────────────────────────────────────────

CREATE TABLE public.dungeon_runs (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tier         int         NOT NULL REFERENCES public.dungeon_tiers(tier),
    status       text        NOT NULL DEFAULT 'in_progress'
                             CHECK (status IN ('in_progress','success','failure','abandoned')),
    multiplier   numeric     NOT NULL DEFAULT 1.0
                             CHECK (multiplier >= 1.0 AND multiplier <= 3.0),
    started_at   timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE public.dungeon_run_choices (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id     uuid        NOT NULL REFERENCES public.dungeon_runs(id) ON DELETE CASCADE,
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    step       int         NOT NULL CHECK (step >= 1),
    choice_key text        NOT NULL,
    skill_used text,
    xp_awarded bigint      NOT NULL DEFAULT 0 CHECK (xp_awarded >= 0),
    chosen_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, step)
);

CREATE TABLE public.dungeon_run_rewards (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id     uuid        NOT NULL REFERENCES public.dungeon_runs(id) ON DELETE CASCADE,
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    item_id    text        NOT NULL REFERENCES public.items(id),
    quantity   bigint      NOT NULL CHECK (quantity > 0),
    granted_at timestamptz NOT NULL DEFAULT now()
);

-- ── Ledger ──────────────────────────────────────────────────

CREATE TABLE public.resource_ledger (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    base_id    uuid        REFERENCES public.player_bases(id) ON DELETE SET NULL,
    item_id    text        NOT NULL REFERENCES public.items(id),
    delta      bigint      NOT NULL,
    reason     text        NOT NULL,
    ref_id     uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- ────────────────────────────────────────────────────────────
-- INDEXES
-- ────────────────────────────────────────────────────────────

CREATE INDEX idx_player_bases_user         ON public.player_bases (user_id);
CREATE INDEX idx_base_inventory_user       ON public.base_inventory (user_id);
CREATE INDEX idx_base_inventory_base       ON public.base_inventory (base_id);
CREATE INDEX idx_base_storage_caps_base    ON public.base_storage_caps (base_id);
CREATE INDEX idx_production_skills_user    ON public.production_skills (user_id);
CREATE INDEX idx_combat_skills_user        ON public.combat_skills (user_id);
CREATE INDEX idx_player_ship_parts_user    ON public.player_ship_parts (user_id);
CREATE INDEX idx_player_ship_equipped_user ON public.player_ship_equipped (user_id);
CREATE INDEX idx_player_ship_upgrades_user ON public.player_ship_upgrades (user_id);
CREATE INDEX idx_player_unlocks_user       ON public.player_unlocks (user_id);
CREATE INDEX idx_dungeon_runs_user_status  ON public.dungeon_runs (user_id, status);
CREATE INDEX idx_dungeon_run_choices_run   ON public.dungeon_run_choices (run_id);
CREATE INDEX idx_dungeon_run_rewards_run   ON public.dungeon_run_rewards (run_id);
CREATE INDEX idx_resource_ledger_user_ts   ON public.resource_ledger (user_id, created_at);
CREATE INDEX idx_idle_prod_rules_base      ON public.idle_production_rules (base_type_id);

-- ────────────────────────────────────────────────────────────
-- ROW-LEVEL SECURITY — static tables (read-only for authenticated)
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.base_types            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dungeon_tiers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idle_production_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ship_upgrade_defs     ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read base_types"
    ON public.base_types FOR SELECT
    TO authenticated USING (true);

CREATE POLICY "Authenticated read items"
    ON public.items FOR SELECT
    TO authenticated USING (true);

CREATE POLICY "Authenticated read dungeon_tiers"
    ON public.dungeon_tiers FOR SELECT
    TO authenticated USING (true);

CREATE POLICY "Authenticated read idle_production_rules"
    ON public.idle_production_rules FOR SELECT
    TO authenticated USING (true);

CREATE POLICY "Authenticated read ship_upgrade_defs"
    ON public.ship_upgrade_defs FOR SELECT
    TO authenticated USING (true);

-- ────────────────────────────────────────────────────────────
-- ROW-LEVEL SECURITY — player-owned tables
-- ────────────────────────────────────────────────────────────

-- Helper: enable RLS + four standard policies per table
-- We spell them out explicitly per the build-spec preference.

-- profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profiles_delete" ON public.profiles FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_state
ALTER TABLE public.player_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_state_select" ON public.player_state FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_state_insert" ON public.player_state FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_state_update" ON public.player_state FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_state_delete" ON public.player_state FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_bases
ALTER TABLE public.player_bases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_bases_select" ON public.player_bases FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_bases_insert" ON public.player_bases FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_bases_update" ON public.player_bases FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_bases_delete" ON public.player_bases FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- base_inventory
ALTER TABLE public.base_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "base_inventory_select" ON public.base_inventory FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "base_inventory_insert" ON public.base_inventory FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "base_inventory_update" ON public.base_inventory FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "base_inventory_delete" ON public.base_inventory FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- base_storage_caps
ALTER TABLE public.base_storage_caps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "base_storage_caps_select" ON public.base_storage_caps FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "base_storage_caps_insert" ON public.base_storage_caps FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "base_storage_caps_update" ON public.base_storage_caps FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "base_storage_caps_delete" ON public.base_storage_caps FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- production_skills
ALTER TABLE public.production_skills ENABLE ROW LEVEL SECURITY;
CREATE POLICY "production_skills_select" ON public.production_skills FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "production_skills_insert" ON public.production_skills FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "production_skills_update" ON public.production_skills FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "production_skills_delete" ON public.production_skills FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- combat_skills
ALTER TABLE public.combat_skills ENABLE ROW LEVEL SECURITY;
CREATE POLICY "combat_skills_select" ON public.combat_skills FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "combat_skills_insert" ON public.combat_skills FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "combat_skills_update" ON public.combat_skills FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "combat_skills_delete" ON public.combat_skills FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_ship
ALTER TABLE public.player_ship ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_ship_select" ON public.player_ship FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_ship_insert" ON public.player_ship FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_update" ON public.player_ship FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_delete" ON public.player_ship FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_ship_parts
ALTER TABLE public.player_ship_parts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_ship_parts_select" ON public.player_ship_parts FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_ship_parts_insert" ON public.player_ship_parts FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_parts_update" ON public.player_ship_parts FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_parts_delete" ON public.player_ship_parts FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_ship_equipped
ALTER TABLE public.player_ship_equipped ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_ship_equipped_select" ON public.player_ship_equipped FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_ship_equipped_insert" ON public.player_ship_equipped FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_equipped_update" ON public.player_ship_equipped FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_equipped_delete" ON public.player_ship_equipped FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_ship_upgrades
ALTER TABLE public.player_ship_upgrades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_ship_upgrades_select" ON public.player_ship_upgrades FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_ship_upgrades_insert" ON public.player_ship_upgrades FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_upgrades_update" ON public.player_ship_upgrades FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_ship_upgrades_delete" ON public.player_ship_upgrades FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- player_unlocks
ALTER TABLE public.player_unlocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_unlocks_select" ON public.player_unlocks FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "player_unlocks_insert" ON public.player_unlocks FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_unlocks_update" ON public.player_unlocks FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "player_unlocks_delete" ON public.player_unlocks FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- dungeon_runs
ALTER TABLE public.dungeon_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dungeon_runs_select" ON public.dungeon_runs FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "dungeon_runs_insert" ON public.dungeon_runs FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_runs_update" ON public.dungeon_runs FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_runs_delete" ON public.dungeon_runs FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- dungeon_run_choices
ALTER TABLE public.dungeon_run_choices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dungeon_run_choices_select" ON public.dungeon_run_choices FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "dungeon_run_choices_insert" ON public.dungeon_run_choices FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_run_choices_update" ON public.dungeon_run_choices FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_run_choices_delete" ON public.dungeon_run_choices FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- dungeon_run_rewards
ALTER TABLE public.dungeon_run_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dungeon_run_rewards_select" ON public.dungeon_run_rewards FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "dungeon_run_rewards_insert" ON public.dungeon_run_rewards FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_run_rewards_update" ON public.dungeon_run_rewards FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dungeon_run_rewards_delete" ON public.dungeon_run_rewards FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- resource_ledger
ALTER TABLE public.resource_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "resource_ledger_select" ON public.resource_ledger FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "resource_ledger_insert" ON public.resource_ledger FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY "resource_ledger_update" ON public.resource_ledger FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "resource_ledger_delete" ON public.resource_ledger FOR DELETE TO authenticated
    USING (auth.uid() = user_id);
