{
  inputs = {
    nixpkgs.follows = "minnows/nixpkgs";

    minnows.url = "https://flakehub.com/f/DeterminateSystems/minnows/*";
    minnows-platform-qemu.url = "https://flakehub.com/f/DeterminateSystems/minnows-platform-qemu/*";
    minnows-flow-debug-shell.url = "https://flakehub.com/f/DeterminateSystems/minnows-flow-debug-shell/*";
  };

  outputs =
    inputs:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forSystem =
        system: f:
        f rec {
          inherit system;
          pkgs = import inputs.nixpkgs {
            inherit system;
          };
          lib = pkgs.lib;
        };
      forAllSystems = f: inputs.nixpkgs.lib.genAttrs supportedSystems (system: (forSystem system f));
    in
    {
      minnowsSystems = forAllSystems (
        { pkgs, system, ... }:
        {
          default = import ./system.nix {
            inherit inputs;
            system = "aarch64-linux";
          };
        }
      );

      checks = forAllSystems (
        { pkgs, system, ... }:
        {
          default = (
            let
              minnows-cli = inputs.minnows.packages.${system}.minnows-cli;
              bootspec = inputs.self.minnowsSystems.${system}.default.bootspec;
            in
            pkgs.runCommand "vmtest" { } ''
              set -x
              set -ueo pipefail

              sbdir="$(mktemp -d)"
              disk="$(mktemp --dry-run)"
              "${minnows-cli}/bin/minnows-cli" sb gen --dir "''${sbdir}"

              "${minnows-cli}/bin/minnows-cli" build-disk \
                --bootspec-path "${bootspec}" \
                --secure-boot-dir "''${sbdir}" \
                --output "''${disk}"

              "${minnows-cli}/bin/minnows-cli" run vmtest \
                --disk "''${disk}" \
                --var-store "''${sbdir}/vars.json" \
                --expect-success "flow-fec1-flakehub-edge-cache.service"

              touch $out
            ''
          );
        }
      );
    };
}
