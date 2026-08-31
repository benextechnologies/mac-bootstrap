#!/usr/bin/env node
// ccstatusline custom-command widget: cumulative session output tokens
// (output_tokens includes thinking tokens; subagent/sidechain responses included).
// Dedupes by message id since Claude Code writes one transcript entry per
// content block, each repeating the same usage object.
const fs = require("fs");
let input = "";
try { input = fs.readFileSync(0, "utf8"); } catch {}
let path = "";
try { path = JSON.parse(input).transcript_path || ""; } catch {}
if (!path || !fs.existsSync(path)) { process.stdout.write("?"); process.exit(0); }
const byId = new Map();
let anon = 0;
for (const line of fs.readFileSync(path, "utf8").split("\n")) {
  if (!line.includes('"output_tokens"')) continue;
  let d; try { d = JSON.parse(line); } catch { continue; }
  const u = d?.message?.usage;
  if (!u || typeof u.output_tokens !== "number") continue;
  byId.set(d.message.id || "anon" + anon++, u.output_tokens);
}
let total = 0;
for (const v of byId.values()) total += v;
process.stdout.write(
  total < 1000 ? String(total)
  : total < 1e6 ? (total / 1000).toFixed(1) + "k"
  : (total / 1e6).toFixed(2) + "M"
);
