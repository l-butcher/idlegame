export type BaseType = "earth" | "moon" | "asteroid" | "europa";

export type ProductionSkillId =
  | "mining"
  | "farming"
  | "ranching"
  | "refining"
  | "crafting"
  | "tech";

export type CombatSkillId = "attack" | "defense" | "health";

export type SkillId = ProductionSkillId | CombatSkillId;

export type RunStatus = "in_progress" | "success" | "failure" | "abandoned";

export type UnlockType = "base" | "location" | "feature";

export type ItemRarity = "common" | "uncommon" | "rare" | "epic" | "legendary";

export interface PlayerState {
  user_id: string;
  display_name: string;
  highest_dungeon_tier: number;
  last_login_at: string;
  last_claim_at: string;
  total_dungeon_runs: number;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
}

export interface Base {
  id: string;
  user_id: string;
  base_type_id: BaseType;
  unlocked_at: string;
  last_claim_at: string;
  [key: string]: unknown;
}

export interface InventoryRow {
  id: string;
  user_id: string;
  base_id: string;
  item_id: string;
  quantity: number;
  updated_at: string;
  [key: string]: unknown;
}

export interface StorageCap {
  id: string;
  user_id: string;
  base_id: string;
  item_id: string;
  cap: number;
  [key: string]: unknown;
}

export interface SkillRow {
  id: string;
  user_id: string;
  skill_id: SkillId;
  level: number;
  xp: number;
  updated_at: string;
  [key: string]: unknown;
}

export interface ShipInfo {
  user_id: string;
  ship_name: string;
  hull_level: number;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
}

export interface ShipPart {
  id: string;
  user_id: string;
  item_id: string;
  quantity: number;
  acquired_at: string;
  [key: string]: unknown;
}

export interface ShipEquipped {
  id: string;
  user_id: string;
  slot: string;
  item_id: string;
  equipped_at: string;
  [key: string]: unknown;
}

export interface ShipUpgrade {
  id: string;
  user_id: string;
  upgrade_def_id: string;
  applied_at: string;
  [key: string]: unknown;
}

export interface Ship {
  info: ShipInfo | Record<string, never>;
  parts: ShipPart[];
  equipped: ShipEquipped[];
  upgrades: ShipUpgrade[];
  [key: string]: unknown;
}

export interface Unlock {
  id: string;
  user_id: string;
  unlock_type: UnlockType;
  unlock_key: string;
  unlocked_at: string;
  [key: string]: unknown;
}

export interface DungeonRun {
  id: string;
  user_id: string;
  tier: number;
  status: RunStatus;
  multiplier: number;
  started_at: string;
  completed_at?: string | null;
  [key: string]: unknown;
}

export interface DungeonReward {
  id: string;
  run_id: string;
  user_id: string;
  item_id: string;
  quantity: number;
  granted_at: string;
  type?: string;
  [key: string]: unknown;
}

export interface PlayerSnapshot {
  player_state: PlayerState | Record<string, never>;
  bases: Base[];
  inventories: InventoryRow[];
  caps: StorageCap[];
  production_skills: SkillRow[];
  combat_skills: SkillRow[];
  ship: Ship;
  unlocks: Unlock[];
  active_run: DungeonRun | Record<string, never>;
  [key: string]: unknown;
}

export interface ClaimDelta {
  item_id: string;
  quantity: number;
}

export interface ClaimBase {
  base_id: string;
  base_type_id: BaseType;
  elapsed_seconds: number;
  deltas: Record<string, number>;
  inventory: Record<string, number>;
  [key: string]: unknown;
}

export interface ClaimAllResponse {
  claimed_at: string;
  bases: ClaimBase[];
  [key: string]: unknown;
}

export interface StartRunResponse {
  run_id: string;
  tier: number;
  tier_name: string;
  duration_seconds: number;
  enemy_power: number;
  [key: string]: unknown;
}

export interface SubmitChoiceResponse {
  choice_id: string;
  run_id: string;
  step: number;
  skill_used: string | null;
  [key: string]: unknown;
}

export interface SubmitMultiplierResponse {
  run_id: string;
  multiplier: number;
  source: string;
  [key: string]: unknown;
}

export interface LevelUp {
  skill_id: SkillId;
  old_level: number;
  new_level: number;
  xp: number;
}

export interface CompleteRunResponse {
  run_id: string;
  outcome: "success" | "failure";
  multiplier: number;
  rewards: DungeonReward[];
  level_ups: LevelUp[];
  new_unlocks: Array<{ type: string; tier?: number; [key: string]: unknown }>;
  [key: string]: unknown;
}

export interface EquipPartResponse {
  slot: string;
  item_id: string;
  equipped: ShipEquipped[];
  [key: string]: unknown;
}

export interface ApplyUpgradeResponse {
  upgrade_id: string;
  new_level: number;
  max_level: number;
  credits_spent: number;
  parts_spent: string[];
  [key: string]: unknown;
}

export interface UnlockResponse {
  unlock_type: UnlockType;
  unlock_key: string;
  unlocked: boolean;
  [key: string]: unknown;
}

export interface AbandonRunResponse {
  run_id: string;
  status: "abandoned";
  [key: string]: unknown;
}
