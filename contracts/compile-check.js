// Best-effort standalone compile check via npm `solc`, since forge itself is unavailable in this
// sandbox (GitHub access scoped away from foundry-rs/foundry — see README.md / DECISIONS.md).
// This is NOT a substitute for `forge build` / `forge test` — no via_ir, no Foundry-specific
// remapping edge cases, no cheatcode execution (Vm calls type-check but don't DO anything here,
// so test results below only prove test files compile, never that they pass). Run wherever forge
// is installed for the real thing.
//
// Usage: node compile-check.js [src|test|all]  (defaults to "all")
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const mode = process.argv[2] || "all";
const dirs = [];
if (mode === "src" || mode === "all") dirs.push(path.join(__dirname, "src"));
if (mode === "test" || mode === "all") dirs.push(path.join(__dirname, "test"));

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".sol")) out.push(full);
  }
  return out;
}

// Also include script/ so it type-checks too (best-effort; Script base itself resolves fine now
// that forge-std is vendored under lib/).
if (mode === "all") dirs.push(path.join(__dirname, "script"));

let files = [];
for (const d of dirs) walk(d, files);

const sources = {};
for (const f of files) {
  const rel = path.relative(__dirname, f);
  sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

// Parse remappings.txt (simple "prefix=target" lines) so forge-std/... and @openzeppelin/...
// both resolve the same way `forge build` would.
const remappings = fs
  .readFileSync(path.join(__dirname, "remappings.txt"), "utf8")
  .split("\n")
  .map((l) => l.trim())
  .filter(Boolean)
  .map((l) => l.split("="));

function findImport(importPath) {
  for (const [prefix, target] of remappings) {
    if (importPath.startsWith(prefix)) {
      const remapped = target + importPath.slice(prefix.length);
      const full = path.join(__dirname, remapped);
      if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
  }
  const candidates = [
    path.join(__dirname, importPath),
    path.join(__dirname, "node_modules", importPath),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return { contents: fs.readFileSync(c, "utf8") };
  }
  return { error: "File not found: " + importPath };
}

const input = {
  language: "Solidity",
  sources,
  settings: {
    evmVersion: "cancun",
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi"] } },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImport }));

let hadError = false;
if (output.errors) {
  for (const err of output.errors) {
    if (err.severity === "error") {
      hadError = true;
      console.error(err.formattedMessage);
    } else {
      console.warn(err.formattedMessage);
    }
  }
}

if (hadError) {
  console.error("\nCompile check FAILED.");
  process.exit(1);
} else {
  console.log("\nCompile check PASSED (solc " + solc.version() + ") — " + files.length + " files (" + mode + "), no errors.");
  console.log("Reminder: this only proves the files are syntactically/type valid, NOT that tests");
  console.log("pass — no cheatcode execution happens here. Run `forge test` for the real thing.");
}
