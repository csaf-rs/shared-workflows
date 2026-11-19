#!/usr/bin/env node
// Post-processes a `wasm-pack build --target web` output directory so the package works
// in browsers and in Node.js with the same import:
//
//   import init, { ... } from "<package>";
//   await init();
//
// - Writes `<name>_node.js`, which initializes the wasm synchronously from disk
//   (the `web` loader would use `fetch()` on a `file://` URL, which Node does not support).
// - Patches `package.json` with an `exports` map that selects the Node entry via the
//   `node` condition and the web entry otherwise.
//
// The shim intentionally has no top-level `await`, so `require()` of it works on
// Node versions with `require(esm)` support (20.19+, 22.12+).
//
// Usage: node node-shim.mjs <pkg-dir>

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: node-shim.mjs <pkg-dir>");
  process.exit(2);
}

const pkgPath = join(dir, "package.json");
const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));

if (typeof pkg.main !== "string" || !pkg.main.endsWith(".js")) {
  console.error(`${pkgPath}: expected "main" to point to a .js file, got ${JSON.stringify(pkg.main)}`);
  process.exit(1);
}
if (pkg.type !== "module") {
  console.error(`${pkgPath}: expected "type": "module" (was this built with --target web?)`);
  process.exit(1);
}

const name = pkg.main.slice(0, -".js".length);
const webEntry = `${name}.js`;
const nodeEntry = `${name}_node.js`;
const wasmFile = `${name}_bg.wasm`;
const typesFile = pkg.types ?? `${name}.d.ts`;

for (const file of [webEntry, wasmFile, typesFile]) {
  try {
    readFileSync(join(dir, file));
  } catch {
    console.error(`${dir}: missing expected file ${file}`);
    process.exit(1);
  }
}

const loader = readFileSync(join(dir, webEntry), "utf8");
if (!/export\s*\{[^}]*\binitSync\b/.test(loader) || !/__wbg_init\b/.test(loader)) {
  console.error(`${webEntry}: does not look like a --target web build (no initSync/default init export)`);
  process.exit(1);
}

const shim = `import { readFileSync } from "node:fs";
import { initSync } from "./${webEntry}";

export * from "./${webEntry}";
export { default } from "./${webEntry}";

initSync({ module: readFileSync(new URL("./${wasmFile}", import.meta.url)) });
`;
writeFileSync(join(dir, nodeEntry), shim);

const unique = (list) => [...new Set(list)];

pkg.files = unique([...(pkg.files ?? []), webEntry, wasmFile, typesFile, nodeEntry]);
pkg.sideEffects = unique([...(Array.isArray(pkg.sideEffects) ? pkg.sideEffects : []), `./${nodeEntry}`]);
pkg.exports = {
  ".": {
    types: `./${typesFile}`,
    node: `./${nodeEntry}`,
    default: `./${webEntry}`,
  },
  [`./${webEntry}`]: `./${webEntry}`,
  [`./${wasmFile}`]: `./${wasmFile}`,
  "./package.json": "./package.json",
};

writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
console.log(`Wrote ${nodeEntry} and patched exports in ${pkgPath}`);
