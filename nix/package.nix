{ lib, buildNpmPackage, fetchNpmDeps, nodejs_26, electron, autoPatchelfHook,
  makeDesktopItem, copyDesktopItems, stdenv, fetchurl }:

let
  fontBase = "https://raw.githubusercontent.com/google/fonts/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl";
  mono = fetchurl {
    name = "JetBrainsMono.ttf";
    url = "${fontBase}/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf";
    hash = "sha256-SHFaQuwkLCHp8CaSiR4UfQIimaUuSNXkE+GpQhk//to=";
  };
  sans = fetchurl {
    name = "SourceSans3.ttf";
    url = "${fontBase}/sourcesans3/SourceSans3%5Bwght%5D.ttf";
    hash = "sha256-BC/izAuTPjKEENesvQqmoYc9ylrvgYdfS8IUsIglx7k=";
  };
  monoLicense = fetchurl {
    name = "JetBrainsMono-OFL.txt";
    url = "${fontBase}/jetbrainsmono/OFL.txt";
    hash = "sha256-sv5eiYdZTp/9HSylKi9dc+uDNSQ4k8XWJUta1pJpWR0=";
  };
  sansLicense = fetchurl {
    name = "SourceSans3-OFL.txt";
    url = "${fontBase}/sourcesans3/OFL.txt";
    hash = "sha256-CXRnhyh6KJMjsOw8/00aSoATMbgrcgfB4Yb10mYZo5I=";
  };

  # Source plugins are separate npm projects with their own lockfiles, which
  # buildNpmPackage's root npmDeps does not cover. `npm run build` compiles the
  # core ones (plugins:build-core) and next build typechecks all of them, so
  # every plugin needs its dependencies, as `npm run plugins:setup` provides.
  # A plugin without a hash here fails evaluation instead of the sandboxed build.
  pluginDepsHashes = {
    coding-questions = "sha256-NWIHJiToak9X1qyMNSlZtMjyFatgIs0RHqmS0QcXzdo=";
    drawing-pad = "sha256-zMTb53SFM4ZQT30ktIu7s+DwqYL1QCN6Mg3ZtF5aCfw=";
    flashcards = "sha256-AGjSn0TFK8jx3VpgAROg9fjhZ7gT6CKBD6vr+FbZJKE=";
    rich-code-blocks = "sha256-/jyfBWOCuludfG1Hg3bXCUqMttXeABe0vt/paW5sSyY=";
    ui-showcase = "sha256-WnG+nUQjvVBnjLRcXwlGq0ubRjBiJoX5ZUvoDWtx+CI=";
  };
  # Same selection as scripts/setup-plugins.mjs: plugin directories with a package.json.
  sourcePlugins = map (id: {
    inherit id;
    # Plugins with an `sdk` script link the generated type-only API package (file:.sdk).
    hasSdk = (lib.importJSON (../plugins + "/${id}/package.json")).scripts ? sdk;
    npmDeps = fetchNpmDeps {
      name = "learnharness-plugin-${id}-npm-deps";
      src = lib.fileset.toSource {
        root = ../plugins + "/${id}";
        fileset = ../plugins + "/${id}/package-lock.json";
      };
      hash = pluginDepsHashes.${id};
    };
  }) (lib.attrNames (lib.filterAttrs
    (id: type: type == "directory" && builtins.pathExists (../plugins + "/${id}/package.json"))
    (builtins.readDir ../plugins)));
in
buildNpmPackage {
  pname = "learnharness";
  version = (lib.importJSON ../package.json).version;
  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: type:
      let
        name = baseNameOf path;
        relative = lib.removePrefix "${toString ../.}/" (toString path);
      in
      lib.cleanSourceFilter path type
      && !(builtins.elem name [ "node_modules" ".next" ".sdk" "data" "auth.json" ".fresh-data" ".memory" "real-data-extraction" "result" ])
      # Only the root build output: examples/plugins/*/dist are tracked inputs to plugin authoring.
      && relative != "dist"
      && !(lib.hasPrefix ".env" name);
  };

  nodejs = nodejs_26;
  npmDepsHash = "sha256-bp7HWZaBNfuqtuguGxD4n1mtpTnMxRdqNvabxNMYRE8=";
  npmFlags = [ "--ignore-scripts" ];
  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    NEXT_TELEMETRY_DISABLED = "1";
    LD_LIBRARY_PATH = lib.makeLibraryPath [ stdenv.cc.cc.lib ];
  };

  nativeBuildInputs = [ autoPatchelfHook copyDesktopItems ];
  buildInputs = [ stdenv.cc.cc.lib ];
  # Electron is already patched by nixpkgs; only patch the npm native modules.
  dontAutoPatchelf = true;
  # Preserve nixpkgs' dlopen-only EGL/Vulkan/PipeWire runtime search paths.
  dontPatchELF = true;
  postFixup = ''
    autoPatchelf "$out/lib/learnharness/resources/server"
  '';

  postPatch = ''
    # Keep the existing font families/weights without network access in next build.
    cp ${mono} public/fonts/JetBrainsMono.ttf
    cp ${sans} public/fonts/SourceSans3.ttf
    substituteInPlace app/layout.tsx \
      --replace-fail 'import { JetBrains_Mono, Source_Sans_3 } from "next/font/google";' 'import localFont from "next/font/local";' \
      --replace-fail 'JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" })' 'localFont({ src: "../public/fonts/JetBrainsMono.ttf", weight: "100 800", display: "swap", variable: "--font-jetbrains" })' \
      --replace-fail 'Source_Sans_3({ subsets: ["latin"], variable: "--font-sans3" })' 'localFont({ src: "../public/fonts/SourceSans3.ttf", weight: "200 900", display: "swap", variable: "--font-sans3" })'
  '';

  # Mirrors `npm run plugins:setup`, offline from each plugin's prefetched cache.
  preBuild = lib.concatMapStrings (plugin: ''
    pushd plugins/${plugin.id}
    ${lib.optionalString plugin.hasSdk "npm run sdk"}
    npm ci --ignore-scripts --offline --no-audit --no-fund --cache ${plugin.npmDeps}
    popd
  '') sourcePlugins;

  postBuild = ''
    node scripts/smoke-provider-runtime.mjs
    chmod -R u+w .next/standalone
    node scripts/build-server.mjs
    # npm also installs Sharp's musl alternative; NixOS uses the glibc variant.
    rm -rf .next/standalone/node_modules/@img/*linuxmusl*
    node scripts/smoke-server.mjs
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/learnharness/resources/app" "$out/bin"
    # A private runtime preserves process.resourcesPath and process.execPath,
    # including the child server and --browser-service helper launches.
    cp -rL ${electron}/libexec/electron/. "$out/lib/learnharness/"
    chmod -R u+w "$out/lib/learnharness"
    rm -f "$out/lib/learnharness/resources/default_app.asar"
    cp -r electron package.json "$out/lib/learnharness/resources/app/"
    mkdir -p "$out/lib/learnharness/resources/server"
    cp -r .next/standalone "$out/lib/learnharness/resources/server/"
    mkdir -p "$out/share/doc/learnharness"
    cp LICENSE docs/compaction-accounting.md "$out/share/doc/learnharness/"
    cp ${monoLicense} "$out/share/doc/learnharness/JetBrainsMono-OFL.txt"
    cp ${sansLicense} "$out/share/doc/learnharness/SourceSans3-OFL.txt"
    # Nix owns updates; do not load the upstream release updater.
    substituteInPlace "$out/lib/learnharness/resources/app/electron/main.cjs" \
      --replace-fail 'if (!app.isPackaged) {' 'if (true) { // Nix-managed build'
    # Retain nixpkgs' GTK/GIO environment, but launch our private runtime.
    install -m755 ${electron}/bin/electron "$out/bin/learnharness"
    substituteInPlace "$out/bin/learnharness" \
      --replace-fail '${electron.unwrapped}/libexec/electron/electron' "$out/lib/learnharness/electron"
    install -Dm444 build/icon.png "$out/share/icons/hicolor/512x512/apps/learnharness.png"
    runHook postInstall
  '';

  desktopItems = [ (makeDesktopItem {
    name = "learnharness";
    desktopName = "LearnHarness";
    exec = "learnharness %U";
    icon = "learnharness";
    categories = [ "Education" ];
    startupWMClass = "learnharness";
  }) ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node scripts/smoke-provider-runtime.mjs \
      --standalone "$out/lib/learnharness/resources/server/standalone" \
      --runtime "$out/bin/learnharness"
    node scripts/smoke-demo-runtime.mjs \
      --standalone "$out/lib/learnharness/resources/server/standalone" \
      --runtime "$out/bin/learnharness"
    runHook postInstallCheck
  '';

  meta = {
    description = "Agent harness for learning difficult things";
    homepage = "https://github.com/dylan-gluck/learnharness";
    license = lib.licenses.agpl3Only;
    mainProgram = "learnharness";
    platforms = [ "x86_64-linux" ];
  };
}
