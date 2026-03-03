import type {
  PlayerSnapshot,
  PlayerState,
  Base,
  InventoryRow,
  StorageCap,
  SkillRow,
  Ship,
  ShipPart,
  Unlock,
  DungeonRun,
  DungeonReward,
  SkillId,
  BaseType,
  ProductionSkillId,
  CombatSkillId,
} from "./contracts";

// ── helpers ─────────────────────────────────────────────────

let _idCounter = 0;
function uid(): string {
  return `mock-${Date.now()}-${++_idCounter}`;
}

function now(): string {
  return new Date().toISOString();
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function chance(pct: number): boolean {
  return Math.random() * 100 < pct;
}

// ── static data ─────────────────────────────────────────────

const USER_ID = "mock-user-0001";
const STORAGE_CAP = 1000;
const XP_PER_LEVEL = 1000;
const OFFLINE_CAP_S = 43200;

const PROD_SKILLS: ProductionSkillId[] = [
  "mining", "farming", "ranching", "refining", "crafting", "tech",
];
const COMBAT_SKILLS: CombatSkillId[] = ["attack", "defense", "health"];

interface BaseConfig {
  type: BaseType;
  locked: boolean;
  resources: string[];
  rates: Record<string, number>;
}

const BASE_CONFIGS: BaseConfig[] = [
  {
    type: "earth",
    locked: false,
    resources: ["ore_iron", "ore_copper", "food_basic", "bio_samples", "credits"],
    rates: { ore_iron: 0.5, ore_copper: 0.3, food_basic: 0.8, bio_samples: 0.2, credits: 0.05 },
  },
  {
    type: "moon",
    locked: true,
    resources: ["ore_iron", "metal_iron", "credits"],
    rates: { ore_iron: 0.8, metal_iron: 0.3, credits: 0.1 },
  },
  {
    type: "asteroid",
    locked: true,
    resources: ["ore_copper", "metal_copper", "circuit_basic", "credits"],
    rates: { ore_copper: 1.0, metal_copper: 0.5, circuit_basic: 0.4, credits: 0.15 },
  },
];

const TIER_NAMES: string[] = [
  "Shallow Cavern", "Dusty Tunnels", "Abandoned Mine", "Crystal Grotto", "Fungal Depths",
  "Flooded Passage", "Lava Vents", "Frozen Rift", "Toxic Warren", "Shadow Hollow",
  "Iron Labyrinth", "Bone Catacombs", "Magma Core", "Void Fissure", "Storm Nexus",
  "Obsidian Maze", "Spectral Halls", "Plasma Tunnels", "Gravity Well", "Chrono Rift",
  "Nebula Depths", "Dark Matter Pit", "Singularity Gate", "Stellar Tomb", "Event Horizon",
];

const RARE_ITEMS = ["crystal_prism", "dark_matter_shard", "quantum_dust", "void_essence", "nova_fragment"];
const SHIP_PARTS = ["ship_engine_mk1", "ship_shield_mk1", "ship_nav_mk1", "ship_hull_plate", "ship_thruster"];
const DUNGEON_CHOICES = ["path_a", "path_b", "path_c"];

// ── in-memory state ─────────────────────────────────────────

let playerState: PlayerState | null = null;
let bases: Base[] = [];
let inventories: InventoryRow[] = [];
let caps: StorageCap[] = [];
let prodSkills: SkillRow[] = [];
let combatSkills: SkillRow[] = [];
let ship: Ship = { info: {}, parts: [], equipped: [], upgrades: [] };
let unlocks: Unlock[] = [];
let activeRun: DungeonRun | null = null;
let runChoiceSkills: string[] = [];

// ── inventory helpers ───────────────────────────────────────

function getOrCreateInv(baseId: string, itemId: string): InventoryRow {
  let row = inventories.find((r) => r.base_id === baseId && r.item_id === itemId);
  if (!row) {
    row = {
      id: uid(), user_id: USER_ID, base_id: baseId,
      item_id: itemId, quantity: 0, updated_at: now(),
    };
    inventories.push(row);
  }
  return row;
}

function getCapFor(baseId: string, itemId: string): number {
  const c = caps.find((r) => r.base_id === baseId && r.item_id === itemId);
  return c ? c.cap : STORAGE_CAP;
}

function addToInventory(baseId: string, itemId: string, qty: number): InventoryRow {
  const row = getOrCreateInv(baseId, itemId);
  const cap = getCapFor(baseId, itemId);
  row.quantity = clamp(row.quantity + qty, 0, cap);
  row.updated_at = now();
  return row;
}

function earthBaseId(): string {
  const b = bases.find((x) => x.base_type_id === "earth");
  return b ? b.id : "";
}

function addShipPart(itemId: string, qty: number): void {
  const existing = ship.parts.find((p) => p.item_id === itemId);
  if (existing) {
    existing.quantity += qty;
  } else {
    ship.parts.push({
      id: uid(), user_id: USER_ID, item_id: itemId,
      quantity: qty, acquired_at: now(),
    });
  }
}

// ── skill helpers ───────────────────────────────────────────

function grantCombatXp(skillId: string, xp: number): void {
  const sk = combatSkills.find((s) => s.skill_id === skillId);
  if (!sk) return;
  sk.xp += xp;
  while (sk.xp >= sk.level * XP_PER_LEVEL) {
    sk.xp -= sk.level * XP_PER_LEVEL;
    sk.level += 1;
  }
  sk.updated_at = now();
}

// ── snapshot builder ────────────────────────────────────────

function buildSnapshot(): PlayerSnapshot {
  return {
    player_state: playerState ?? ({} as Record<string, never>),
    bases: [...bases],
    inventories: inventories.map((r) => ({ ...r })),
    caps: caps.map((r) => ({ ...r })),
    production_skills: prodSkills.map((r) => ({ ...r })),
    combat_skills: combatSkills.map((r) => ({ ...r })),
    ship: {
      info: ship.info ? { ...ship.info } : {},
      parts: ship.parts.map((p) => ({ ...p })),
      equipped: ship.equipped.map((e) => ({ ...e })),
      upgrades: ship.upgrades.map((u) => ({ ...u })),
    },
    unlocks: unlocks.map((u) => ({ ...u })),
    active_run: activeRun ? { ...activeRun } : ({} as Record<string, never>),
  };
}

// ── RPC implementations ─────────────────────────────────────

export async function bootstrapPlayer(): Promise<PlayerSnapshot> {
  if (playerState) return buildSnapshot();

  const ts = now();

  playerState = {
    user_id: USER_ID,
    display_name: "Space Cadet",
    highest_dungeon_tier: 0,
    last_login_at: ts,
    last_claim_at: ts,
    total_dungeon_runs: 0,
    created_at: ts,
    updated_at: ts,
  };

  for (const cfg of BASE_CONFIGS) {
    const base: Base = {
      id: uid(), user_id: USER_ID, base_type_id: cfg.type,
      unlocked_at: ts, last_claim_at: ts,
    };
    bases.push(base);

    for (const res of cfg.resources) {
      caps.push({
        id: uid(), user_id: USER_ID, base_id: base.id,
        item_id: res, cap: STORAGE_CAP,
      });
    }

    if (!cfg.locked) {
      getOrCreateInv(base.id, "credits").quantity = 100;
      unlocks.push({
        id: uid(), user_id: USER_ID, unlock_type: "base",
        unlock_key: cfg.type, unlocked_at: ts,
      });
    }
  }

  prodSkills = PROD_SKILLS.map((s) => ({
    id: uid(), user_id: USER_ID, skill_id: s as SkillId,
    level: 1, xp: 0, updated_at: ts,
  }));

  combatSkills = COMBAT_SKILLS.map((s) => ({
    id: uid(), user_id: USER_ID, skill_id: s as SkillId,
    level: 1, xp: 0, updated_at: ts,
  }));

  ship = {
    info: {
      user_id: USER_ID, ship_name: "Starter Ship", hull_level: 1,
      created_at: ts, updated_at: ts,
    },
    parts: [],
    equipped: [],
    upgrades: [],
  };

  return buildSnapshot();
}

export async function getPlayerSnapshot(): Promise<PlayerSnapshot> {
  if (!playerState) throw new Error("Player not bootstrapped");
  return buildSnapshot();
}

export async function claimAll(
  baseType: string | null,
): Promise<{ deltas: InventoryRow[]; snapshot: PlayerSnapshot }> {
  if (!playerState) throw new Error("Player not bootstrapped");

  const ts = now();
  const deltas: InventoryRow[] = [];

  for (const base of bases) {
    if (baseType !== null && base.base_type_id !== baseType) continue;

    const isLocked = !unlocks.some(
      (u) => u.unlock_type === "base" && u.unlock_key === base.base_type_id,
    );
    if (isLocked) continue;

    const cfg = BASE_CONFIGS.find((c) => c.type === base.base_type_id);
    if (!cfg) continue;

    const elapsedMs = new Date(ts).getTime() - new Date(base.last_claim_at).getTime();
    const elapsedS = clamp(elapsedMs / 1000, 0, OFFLINE_CAP_S);
    if (elapsedS <= 0) continue;

    for (const res of cfg.resources) {
      const rate = cfg.rates[res] ?? 0;
      const produced = Math.floor(rate * elapsedS);
      if (produced <= 0) continue;

      const row = addToInventory(base.id, res, produced);
      deltas.push({ ...row });
    }

    base.last_claim_at = ts;
  }

  playerState.last_claim_at = ts;
  playerState.updated_at = ts;

  return { deltas, snapshot: buildSnapshot() };
}

export async function startDungeonRun(
  tier: number,
): Promise<{ run: DungeonRun; choices: string[] }> {
  if (!playerState) throw new Error("Player not bootstrapped");
  if (activeRun) throw new Error("A dungeon run is already in progress");
  if (tier < 1 || tier > 25) throw new Error("Invalid tier");
  if (tier > playerState.highest_dungeon_tier + 1) throw new Error("Tier not unlocked");

  const ts = now();
  activeRun = {
    id: uid(), user_id: USER_ID, tier, status: "in_progress",
    multiplier: 1.0, started_at: ts, completed_at: null,
  };
  runChoiceSkills = [];

  playerState.total_dungeon_runs += 1;
  playerState.updated_at = ts;

  return { run: { ...activeRun }, choices: [...DUNGEON_CHOICES] };
}

export async function submitRunChoice(
  runId: string,
  choiceKey: string,
  skillsUsed: string[],
): Promise<DungeonRun> {
  if (!activeRun || activeRun.id !== runId) throw new Error("Run not found");
  if (activeRun.status !== "in_progress") throw new Error("Run is not in progress");

  for (const s of skillsUsed) runChoiceSkills.push(s);
  return { ...activeRun };
}

export async function submitMultiplier(
  runId: string,
  multiplier: number,
  _source: string,
): Promise<DungeonRun> {
  if (!activeRun || activeRun.id !== runId) throw new Error("Run not found");
  if (activeRun.status !== "in_progress") throw new Error("Run is not in progress");

  activeRun.multiplier = clamp(multiplier, 1.0, 3.0);
  return { ...activeRun };
}

export async function completeDungeonRun(
  runId: string,
  outcome: "success" | "fail",
): Promise<{ rewards: DungeonReward[]; snapshot: PlayerSnapshot }> {
  if (!activeRun || activeRun.id !== runId) throw new Error("Run not found");
  if (activeRun.status !== "in_progress") throw new Error("Run is not in progress");
  if (!playerState) throw new Error("Player not bootstrapped");

  const ts = now();
  const tier = activeRun.tier;
  const mult = activeRun.multiplier;
  const factor = outcome === "success" ? 1.0 : 0.5;
  const baseCredits = 50 + (tier - 1) * 100;
  const baseXp = 100 + (tier - 1) * 200;
  const eBase = earthBaseId();

  const rewards: DungeonReward[] = [];

  const creditQty = Math.floor(baseCredits * mult * factor);
  if (creditQty > 0) {
    addToInventory(eBase, "credits", creditQty);
    rewards.push({
      id: uid(), run_id: runId, user_id: USER_ID,
      item_id: "credits", quantity: creditQty, granted_at: ts,
    });
  }

  const oreQty = Math.floor(tier * 5 * mult * factor);
  if (oreQty > 0) {
    addToInventory(eBase, "ore_iron", oreQty);
    rewards.push({
      id: uid(), run_id: runId, user_id: USER_ID,
      item_id: "ore_iron", quantity: oreQty, granted_at: ts,
    });
  }

  const foodQty = Math.floor(tier * 4 * mult * factor);
  if (foodQty > 0) {
    addToInventory(eBase, "food_basic", foodQty);
    rewards.push({
      id: uid(), run_id: runId, user_id: USER_ID,
      item_id: "food_basic", quantity: foodQty, granted_at: ts,
    });
  }

  if (tier >= 3 && chance(tier * 3)) {
    const rare = pick(RARE_ITEMS);
    addToInventory(eBase, rare, 1);
    rewards.push({
      id: uid(), run_id: runId, user_id: USER_ID,
      item_id: rare, quantity: 1, granted_at: ts, type: "rare",
    });
  }

  if (tier >= 5 && chance(tier * 2)) {
    const part = pick(SHIP_PARTS);
    addShipPart(part, 1);
    rewards.push({
      id: uid(), run_id: runId, user_id: USER_ID,
      item_id: part, quantity: 1, granted_at: ts, type: "ship_part",
    });
  }

  const xpPool = Math.floor(baseXp * mult * factor);
  const combatUsed = runChoiceSkills.filter((s) =>
    (COMBAT_SKILLS as readonly string[]).includes(s),
  );
  const targets = combatUsed.length > 0 ? [...new Set(combatUsed)] : [...COMBAT_SKILLS];
  const xpEach = Math.floor(xpPool / targets.length);
  for (const sk of targets) {
    grantCombatXp(sk, xpEach);
  }

  if (outcome === "success" && tier > playerState.highest_dungeon_tier) {
    playerState.highest_dungeon_tier = tier;
  }

  activeRun.status = outcome === "success" ? "success" : "failure";
  activeRun.completed_at = ts;
  playerState.updated_at = ts;

  const finishedRun = { ...activeRun };
  activeRun = null;
  runChoiceSkills = [];

  return { rewards, snapshot: buildSnapshot() };
}
