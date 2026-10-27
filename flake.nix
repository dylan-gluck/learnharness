{
  description = "LearnHarness source-built desktop app and development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      electron = pkgs.electron_44;
      learnharness = pkgs.callPackage ./nix/package.nix { inherit electron; };
    in
    {
      packages.${system} = {
        inherit learnharness;
        default = learnharness;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nodejs_26 pkgs.prefetch-npm-deps electron ];
        ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
        ELECTRON_OVERRIDE_DIST_PATH = "${electron}/libexec/electron";
        NEXT_TELEMETRY_DISABLED = "1";
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
      };
    };
}
