import { createClient } from "@supabase/supabase-js";

const { SUPABASE_URL, SUPABASE_ANON_KEY, EMAIL, PASSWORD } = process.env;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !EMAIL || !PASSWORD) {
  console.error(
    "Missing env vars. Required: SUPABASE_URL, SUPABASE_ANON_KEY, EMAIL, PASSWORD"
  );
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

function pp(label, data) {
  console.log(`\n── ${label} ${"─".repeat(Math.max(0, 60 - label.length))}`);
  console.log(JSON.stringify(data, null, 2));
}

async function rpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params);
  if (error) {
    console.error(`\n✖ ${name} failed:`, error.message);
    process.exit(1);
  }
  pp(name, data);
  return data;
}

function extractRunId(data) {
  for (const key of ["run_id", "runId", "id", "dungeon_run_id"]) {
    if (data?.[key]) return data[key];
  }
  return null;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function main() {
  // ── sign in ───────────────────────────────────────────────
  console.log(`Signing in as ${EMAIL} …`);
  const { error: authErr } = await supabase.auth.signInWithPassword({
    email: EMAIL,
    password: PASSWORD,
  });
  if (authErr) {
    console.log("Sign-in failed; attempting sign-up …");
    const { error: signUpErr } = await supabase.auth.signUp({
      email: EMAIL,
      password: PASSWORD,
    });
    if (signUpErr) {
      console.error("Sign-up failed:", signUpErr.message);
      process.exit(1);
    }
  }
  console.log("✔ Authenticated");

  // 1) bootstrap
  await rpc("rpc_bootstrap_player");

  // 2) snapshot
  await rpc("rpc_get_player_snapshot");

  // 3) wait 5 s (accumulate idle resources)
  console.log("\n⏳ Waiting 5 seconds for idle accrual …");
  await sleep(5000);

  // 4) claim all
  await rpc("rpc_claim_all", { p_base_type: null });

  // 5) start dungeon run
  const startData = await rpc("rpc_start_dungeon_run", { p_tier: 1 });

  let runId = extractRunId(startData);
  if (!runId) {
    console.log("run_id not in start response; reading from snapshot …");
    const snap = await rpc("rpc_get_player_snapshot");
    runId = snap?.active_run?.id ?? extractRunId(snap?.active_run ?? {});
    if (!runId) {
      console.error("✖ Could not determine run_id");
      process.exit(1);
    }
  }
  console.log(`\n🎯 run_id = ${runId}`);

  // 6) submit choice
  await rpc("rpc_submit_run_choice", {
    p_run_id: runId,
    p_choice_key: "path_a",
    p_skills_used: ["attack"],
  });

  // 7) submit multiplier
  await rpc("rpc_submit_multiplier", {
    p_run_id: runId,
    p_multiplier: 2.0,
    p_source: "timing",
  });

  // 8) complete run
  await rpc("rpc_complete_dungeon_run", {
    p_run_id: runId,
    p_outcome: "success",
  });

  // 9) final snapshot
  await rpc("rpc_get_player_snapshot");

  console.log("\n✅ Smoke test passed");
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
