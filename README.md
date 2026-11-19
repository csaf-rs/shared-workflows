# shared-workflows
This is a container for different workflow templates used in our repositories

## Actions

### `wasm-npm-package`

Builds a wasm-bindgen npm package with `wasm-pack` that works in browsers and in Node.js
with the same code, and verifies it. Publishing stays in the calling workflow, because npm trusted
publishing is bound to the caller's workflow file.

```js
import init, { parse } from "@csaf-rs/vers-rs";

await init(); // required in browsers, a no-op in Node.js
```

What the action does:

1. Builds with `wasm-pack build --release --target web`. The `web` target needs no bundler in browsers.
2. Writes `<name>_node.js`, which initializes the wasm synchronously from disk, as the `web` loader
   uses `fetch()`, which does not work for `file://` URLs in Node.js.
3. Patches the generated `package.json` with an `exports` map: the `node` condition selects the
   Node.js entry, everything else the web entry. The `.wasm` file is exported as `./<name>_bg.wasm` for
   runtimes and bundlers that want to load it themselves (`initSync` / `init({ module_or_path })`).
4. Smoke test: packs the package, installs the tarball into a scratch project and loads it from Node.js
   via `import` and `require()`.

Node.js 20.19+ / 22.12+ must be on the `PATH` (`require()` of the ES module entry needs `require(esm)`).
Set it up with `actions/setup-node` before the action, which keeps your `registry-url` configuration.

```yaml
- name: Set up Node
  uses: actions/setup-node@...
  with:
    node-version: 24
    registry-url: "https://registry.npmjs.org"
- name: Build npm package
  uses: csaf-rs/shared-workflows/.github/actions/wasm-npm-package@<sha>
  with:
    readme: NPM-README.md # optional
- name: Publish
  working-directory: pkg
  run: npm publish --provenance
```

| Input               | Default            | Description                                                      |
|---------------------|--------------------|------------------------------------------------------------------|
| `scope`             | `csaf-rs`          | npm scope passed to wasm-pack                                    |
| `out-dir`           | `pkg`              | Output directory of the package                                  |
| `cargo-args`        | `--features wasm`  | Arguments passed to cargo after `--`                             |
| `readme`            | (none)             | Replaces the generated package README                            |
| `working-directory` | `.`                | Directory of the Rust crate                                      |
| `smoke-test`        | `true`             | Pack, install and load the package in Node.js                    |

The Node.js entry has no top-level `await` on purpose, so `require()` keeps working.
