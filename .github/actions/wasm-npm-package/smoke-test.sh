#!/usr/bin/env bash
# Packs a wasm-pack output directory, installs the tarball into a scratch project
# and checks that it can be loaded from Node.js (ESM and CommonJS).
#
# Usage: smoke-test.sh <pkg-dir>
set -euo pipefail

PKG_DIR="$(cd "${1:?usage: smoke-test.sh <pkg-dir>}" && pwd)"
PKG_NAME="$(node -p "require('$PKG_DIR/package.json').name")"
BASE_NAME="$(node -p "require('$PKG_DIR/package.json').main.replace(/\.js$/, '')")"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Packing $PKG_NAME"
TARBALL="$(cd "$PKG_DIR" && npm pack --pack-destination "$WORK_DIR" --silent | tail -n 1)"

cd "$WORK_DIR"
npm init -y --silent > /dev/null
npm pkg set type=module > /dev/null
npm install --silent --no-audit --no-fund "./$TARBALL"

echo "Checking that the web entry does not depend on Node.js built-ins"
if grep -Eq "from ['\"](node:|fs['\"]|path['\"])|require\(" "node_modules/$PKG_NAME/$BASE_NAME.js"; then
  echo "::error::$BASE_NAME.js (browser entry) references Node.js built-ins"
  exit 1
fi

echo "Checking ESM import in Node.js $(node --version)"
cat > check.mjs <<EOF
import init, * as mod from "$PKG_NAME";
import assert from "node:assert/strict";

assert.equal(typeof init, "function", "default export must be the init function");
const exported = Object.keys(mod).filter((k) => k !== "default");
assert.ok(exported.length > 0, "package must export something besides default");

// The Node entry has already initialized the wasm, so init() must be a no-op that resolves.
await init();

assert.ok(import.meta.resolve("$PKG_NAME/${BASE_NAME}_bg.wasm"), "wasm subpath must be exported");
assert.ok(import.meta.resolve("$PKG_NAME/${BASE_NAME}.js"), "web entry subpath must be exported");

const webEntry = await import("$PKG_NAME/${BASE_NAME}.js");
assert.equal(typeof webEntry.default, "function", "web entry must export init");

console.log("ESM ok, exports:", exported.join(", "));
EOF
node check.mjs

echo "Checking CommonJS require()"
cat > check.cjs <<EOF
const assert = require("node:assert/strict");
const mod = require("$PKG_NAME");
assert.ok(Object.keys(mod).length > 0, "require() must expose exports");
console.log("CJS ok");
EOF
node check.cjs

echo "Smoke test passed for $PKG_NAME"
