{ lib, buildNpmPackage, nodejs_26, electron, autoPatchelfHook,
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
in
buildNpmPackage {
  pname = "learnharness";
  version = (lib.importJSON ../package.json).version;
  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: type:
      let name = baseNameOf path; in
      lib.cleanSourceFilter path type
      && !(builtins.elem name [ "node_modules" ".next" "dist" "data" "auth.json" ".fresh-data" ".memory" "real-data-extraction" "result" ])
      && !(lib.hasPrefix ".env" name);
  };

  nodejs = nodejs_26;
  npmDepsHash = "sha256-Sc41l0dUM/R6LV8/DNbbSsgq6gKB4nI2Utf5vqvY84M=";
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
