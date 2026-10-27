# Nix development and desktop builds

The flake supports `x86_64-linux`. It builds LearnHarness's frontend and
standalone agent backend from this source tree, using Node.js 26 and nixpkgs'
Electron 44 runtime. It does not download an upstream LearnHarness AppImage.

## Development

```sh
nix develop path:.
npm ci
npm run dev
# Or run the Electron shell alongside the development server:
npm run desktop:dev
```

The shell points the npm Electron launcher at Nix's compatible runtime, so npm
need not download an unpatched Electron binary. Development uses the normal
upstream font pipeline and can require network access on the first Next build.

## Build and run

```sh
nix build path:.
./result/bin/learnharness
# Alternatively:
nix run path:.
```

`path:.` includes newly added flake files before they are tracked by Git. For a
Git-backed flake reference (`nix build .`), track the new Nix files first.

The package uses the existing standalone-payload and offline provider/server
smoke checks. Native npm modules are patched for NixOS. The existing JetBrains
Mono and Source Sans 3 families are fetched with fixed hashes and substituted
with local font loading **only in the build tree**, allowing sandboxed builds
without network access. Nix owns application updates; the upstream updater is
disabled in the packaged shell. User data remains under the existing
`LearnHarness` application directory.

When changing `package-lock.json`, update `npmDepsHash` in `nix/package.nix`.
`prefetch-npm-deps package-lock.json` is available in the development shell.

## This machine's desktop integration

`/home/dylan/nix/flake.nix` consumes `path:/home/dylan/fork/learnharness` and
shares its nixpkgs input with this flake. The desktop module overrides the
package to inject Noctalia's entry point and transparent Linux window; the
Noctalia JavaScript, CSS, and template configuration remain in the desktop
configuration, not this repository.

Local path inputs are **snapshots pinned by the desktop lock file**, not live
imports. After editing this checkout, refresh that input before switching:

```sh
nix flake update learnharness --flake path:/home/dylan/nix
nix build path:/home/dylan/nix#learnharness
sudo nixos-rebuild switch --flake path:/home/dylan/nix#fwp
```

No GitHub push is required. The first command captures local edits; the switch
builds the themed source package if it is not already in the Nix store. Keep
this checkout at the configured path, or update the desktop input URL.
