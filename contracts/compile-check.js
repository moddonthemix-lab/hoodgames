// Best-effort standalone compile check via npm `solc`, since forge itself is unavailable in this
// sandbox (GitHub access scoped away from foundry-rs/foundry — see README.md / DECISIONS.md).
// This is NOT a substitute for `forge build` / `forge test` — no libs=["node_modules"] handling,
// no Foundry-specific remapping edge cases, no optimizer settings, no test compilation. It only
// catches syntax/type errors in src/. Run wherever forge is installed for the real thing.
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const srcDir = path.join(__dirname, "src");

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".sol")) out.push(full);
  }
  return out;
}

const files = walk(srcDir);
const sources = {};
for (const f of files) {
  const rel = path.relative(__dirname, f);
  sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

function findImport(importPath) {
  const candidates = [
    path.join(__dirname, importPath),
    path.join(__dirname, "node_modules", importPath),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return { contents: fs.readFileSync(c, "utf8") };
    }
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
  console.log("\nCompile check PASSED (solc " + solc.version() + ") — " + files.length + " files, no errors.");
  console.log("Reminder: this only proves src/ is syntactically/type valid. Run `forge build` and");
  console.log("`forge test` for the real thing once forge is available (see README.md).");
}
