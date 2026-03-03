-- ============================================================
-- seed.sql — V1 static / content data
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- BASE TYPES
-- ────────────────────────────────────────────────────────────

INSERT INTO public.base_types (id, name, sort_order, unlock_requirement, available_in_v1) VALUES
    ('earth',    'Earth',    1, NULL,                           true),
    ('moon',     'Moon',     2, 'Ship upgrade: nav_computer L2', true),
    ('asteroid', 'Asteroid', 3, 'Ship upgrade: nav_computer L3', true),
    ('europa',   'Europa',   4, 'Ship upgrade: nav_computer L5', false);

-- ────────────────────────────────────────────────────────────
-- ITEMS
-- ────────────────────────────────────────────────────────────

INSERT INTO public.items (id, name, category, rarity, stackable, description) VALUES
    -- currency
    ('credits',       'Credits',         'currency',  'common',    true,  'Universal currency used across all stations'),

    -- base resources / materials
    ('ore_iron',      'Iron Ore',        'resource',  'common',    true,  'Raw iron extracted from rock'),
    ('ore_copper',    'Copper Ore',      'resource',  'common',    true,  'Raw copper extracted from rock'),
    ('food_basic',    'Basic Rations',   'resource',  'common',    true,  'Simple nutritious food supply'),
    ('bio_samples',   'Bio Samples',     'resource',  'common',    true,  'Organic matter collected for research'),
    ('metal_iron',    'Iron Ingot',      'resource',  'common',    true,  'Refined iron ready for crafting'),
    ('metal_copper',  'Copper Ingot',    'resource',  'common',    true,  'Refined copper ready for crafting'),
    ('circuit_basic', 'Basic Circuit',   'resource',  'common',    true,  'Simple electronic component'),

    -- rare items (dungeon drops)
    ('crystal_prism',      'Crystal Prism',      'misc', 'rare',      true,  'A prismatic crystal humming with energy'),
    ('dark_matter_shard',  'Dark Matter Shard',  'misc', 'epic',      true,  'Fragment of compressed dark matter'),
    ('nova_fragment',      'Nova Fragment',      'misc', 'legendary', false, 'Remnant of a collapsed star'),
    ('alien_artifact',     'Alien Artifact',     'misc', 'epic',      false, 'Mysterious object of unknown origin'),
    ('quantum_dust',       'Quantum Dust',       'misc', 'rare',      true,  'Particles that phase between dimensions'),
    ('void_essence',       'Void Essence',       'misc', 'rare',      true,  'Distilled emptiness from deep space'),

    -- ship parts (6+)
    ('ship_engine_mk1',  'Engine Mk I',    'ship_part', 'uncommon', false, 'Standard propulsion unit'),
    ('ship_engine_mk2',  'Engine Mk II',   'ship_part', 'rare',     false, 'Enhanced propulsion unit'),
    ('ship_shield_mk1',  'Shield Mk I',    'ship_part', 'uncommon', false, 'Basic energy shield emitter'),
    ('ship_shield_mk2',  'Shield Mk II',   'ship_part', 'rare',     false, 'Reinforced energy shield emitter'),
    ('ship_nav_mk1',     'Nav Module Mk I', 'ship_part', 'uncommon', false, 'Guidance computer for short-range travel'),
    ('ship_nav_mk2',     'Nav Module Mk II','ship_part', 'rare',     false, 'Guidance computer for deep-space travel'),
    ('ship_hull_plate',  'Hull Plate',      'ship_part', 'uncommon', false, 'Armoured hull reinforcement panel'),
    ('ship_thruster',    'Thruster Pack',   'ship_part', 'uncommon', false, 'Auxiliary thruster for manoeuvrability');

-- ────────────────────────────────────────────────────────────
-- DUNGEON TIERS 1..25
-- ────────────────────────────────────────────────────────────

INSERT INTO public.dungeon_tiers
    (tier, name, min_combat_power, base_reward_credits, base_reward_xp, duration_seconds, enemy_power)
VALUES
    ( 1, 'Shallow Cavern',    0,   50,   100, 120,  10),
    ( 2, 'Dusty Tunnels',    10,  100,   200, 127,  30),
    ( 3, 'Abandoned Mine',   25,  160,   320, 135,  55),
    ( 4, 'Crystal Grotto',   45,  230,   460, 142,  80),
    ( 5, 'Fungal Depths',    70,  310,   620, 150, 110),
    ( 6, 'Flooded Passage', 100,  400,   800, 157, 145),
    ( 7, 'Lava Vents',      135,  500,  1000, 165, 180),
    ( 8, 'Frozen Rift',     175,  610,  1220, 172, 220),
    ( 9, 'Toxic Warren',    220,  730,  1460, 180, 265),
    (10, 'Shadow Hollow',   270,  860,  1720, 187, 310),
    (11, 'Iron Labyrinth',  325,  1000, 2000, 195, 360),
    (12, 'Bone Catacombs',  385, 1150,  2300, 202, 415),
    (13, 'Magma Core',      450, 1310,  2620, 210, 475),
    (14, 'Void Fissure',    520, 1480,  2960, 217, 540),
    (15, 'Storm Nexus',     595, 1660,  3320, 225, 610),
    (16, 'Obsidian Maze',   675, 1850,  3700, 232, 685),
    (17, 'Spectral Halls',  760, 2050,  4100, 240, 765),
    (18, 'Plasma Tunnels',  850, 2260,  4520, 247, 850),
    (19, 'Gravity Well',    945, 2480,  4960, 255, 940),
    (20, 'Chrono Rift',    1045, 2710,  5420, 262, 1035),
    (21, 'Nebula Depths',  1150, 2950,  5900, 270, 1135),
    (22, 'Dark Matter Pit',1260, 3200,  6400, 277, 1240),
    (23, 'Singularity Gate',1375,3460,  6920, 285, 1350),
    (24, 'Stellar Tomb',   1495, 3730,  7460, 292, 1465),
    (25, 'Event Horizon',  1620, 4010,  8020, 300, 1585);

-- ────────────────────────────────────────────────────────────
-- IDLE PRODUCTION RULES  (earth only for V1)
-- ────────────────────────────────────────────────────────────

INSERT INTO public.idle_production_rules
    (base_type_id, item_id, rate_per_second, skill_id, skill_bonus_pct)
VALUES
    ('earth', 'ore_iron',      0.50, 'mining',   2.0),
    ('earth', 'ore_copper',    0.30, 'mining',   2.0),
    ('earth', 'food_basic',    0.80, 'farming',  2.0),
    ('earth', 'bio_samples',   0.20, 'ranching', 2.5),
    ('earth', 'metal_iron',    0.10, 'refining', 3.0),
    ('earth', 'metal_copper',  0.08, 'refining', 3.0),
    ('earth', 'credits',       0.05, 'crafting', 1.5),
    ('earth', 'circuit_basic', 0.15, 'tech',     2.5);

-- ────────────────────────────────────────────────────────────
-- SHIP UPGRADE DEFS  (6 upgrade lines with levelled costs/effects)
-- ────────────────────────────────────────────────────────────

INSERT INTO public.ship_upgrade_defs
    (id, name, description, required_parts, required_credits, effect, sort_order)
VALUES
(
    'hull_reinforcement',
    'Hull Reinforcement',
    'Reinforce the ship hull to withstand more damage.',
    '["ship_hull_plate"]'::jsonb,
    500,
    '{
        "max_level": 5,
        "stat": "hull_hp",
        "levels": [
            {"level":1, "credits":500,  "parts":["ship_hull_plate"],   "bonus":50},
            {"level":2, "credits":1200, "parts":["ship_hull_plate"],   "bonus":120},
            {"level":3, "credits":2500, "parts":["ship_hull_plate"],   "bonus":220},
            {"level":4, "credits":5000, "parts":["ship_hull_plate","ship_hull_plate"], "bonus":350},
            {"level":5, "credits":10000,"parts":["ship_hull_plate","ship_hull_plate"], "bonus":500}
        ]
    }'::jsonb,
    1
),
(
    'engine_boost',
    'Engine Boost',
    'Upgrade engines for faster travel between locations.',
    '["ship_engine_mk1"]'::jsonb,
    400,
    '{
        "max_level": 5,
        "stat": "travel_speed",
        "levels": [
            {"level":1, "credits":400,  "parts":["ship_engine_mk1"], "bonus":10},
            {"level":2, "credits":1000, "parts":["ship_engine_mk1"], "bonus":25},
            {"level":3, "credits":2200, "parts":["ship_engine_mk2"], "bonus":45},
            {"level":4, "credits":4500, "parts":["ship_engine_mk2"], "bonus":70},
            {"level":5, "credits":9000, "parts":["ship_engine_mk2","ship_thruster"], "bonus":100}
        ]
    }'::jsonb,
    2
),
(
    'shield_generator',
    'Shield Generator',
    'Install and upgrade energy shields for combat protection.',
    '["ship_shield_mk1"]'::jsonb,
    600,
    '{
        "max_level": 4,
        "stat": "shield_hp",
        "levels": [
            {"level":1, "credits":600,  "parts":["ship_shield_mk1"], "bonus":30},
            {"level":2, "credits":1500, "parts":["ship_shield_mk1"], "bonus":70},
            {"level":3, "credits":3500, "parts":["ship_shield_mk2"], "bonus":130},
            {"level":4, "credits":7500, "parts":["ship_shield_mk2","ship_shield_mk2"], "bonus":200}
        ]
    }'::jsonb,
    3
),
(
    'cargo_expansion',
    'Cargo Expansion',
    'Expand cargo bays to increase base storage caps.',
    '["ship_hull_plate"]'::jsonb,
    300,
    '{
        "max_level": 5,
        "stat": "storage_cap_mult",
        "levels": [
            {"level":1, "credits":300,  "parts":["ship_hull_plate"],  "bonus":1.2},
            {"level":2, "credits":800,  "parts":["ship_hull_plate"],  "bonus":1.5},
            {"level":3, "credits":1800, "parts":["ship_hull_plate"],  "bonus":2.0},
            {"level":4, "credits":4000, "parts":["ship_hull_plate","ship_hull_plate"], "bonus":2.8},
            {"level":5, "credits":8000, "parts":["ship_hull_plate","ship_hull_plate"], "bonus":4.0}
        ]
    }'::jsonb,
    4
),
(
    'nav_computer',
    'Navigation Computer',
    'Upgrade navigation to unlock new base locations.',
    '["ship_nav_mk1"]'::jsonb,
    800,
    '{
        "max_level": 5,
        "stat": "nav_range",
        "levels": [
            {"level":1, "credits":800,   "parts":["ship_nav_mk1"],  "bonus":1, "unlocks":"moon"},
            {"level":2, "credits":2000,  "parts":["ship_nav_mk1"],  "bonus":2, "unlocks":"moon"},
            {"level":3, "credits":5000,  "parts":["ship_nav_mk2"],  "bonus":3, "unlocks":"asteroid"},
            {"level":4, "credits":12000, "parts":["ship_nav_mk2"],  "bonus":4},
            {"level":5, "credits":25000, "parts":["ship_nav_mk2","ship_nav_mk2"], "bonus":5, "unlocks":"europa"}
        ]
    }'::jsonb,
    5
),
(
    'weapon_array',
    'Weapon Array',
    'Mount and improve weapons for dungeon combat effectiveness.',
    '["ship_engine_mk1"]'::jsonb,
    500,
    '{
        "max_level": 4,
        "stat": "combat_power",
        "levels": [
            {"level":1, "credits":500,  "parts":["ship_engine_mk1"],  "bonus":15},
            {"level":2, "credits":1300, "parts":["ship_engine_mk1"],  "bonus":35},
            {"level":3, "credits":3000, "parts":["ship_engine_mk2","ship_thruster"], "bonus":65},
            {"level":4, "credits":7000, "parts":["ship_engine_mk2","ship_thruster"], "bonus":100}
        ]
    }'::jsonb,
    6
);
