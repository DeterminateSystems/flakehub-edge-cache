{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*";

    determinate.url = "github:DeterminateSystems/determinate/v3.15.2";
    determinate.inputs = {
      nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      # Exposed systems for the devShells (the module doesn't care)
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forEachSystem =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          f pkgs
        );

    in
    {
      nixosModules.default = import ./modules/default.nix;

      # Test VMs that can be built with `nixos-rebuild build-vm --flake .#x86_64-vm` (or `.#aarch64-vm`).
      nixosConfigurations.x86_64-vm = import ./test/vm.nix {
        system = "x86_64-linux";
        inherit inputs;
      };

      nixosConfigurations.aarch64-vm = import ./test/vm.nix {
        system = "aarch64-linux";
        inherit inputs;
      };

      minnowsFlows.default = import ./flow.nix { inherit inputs; };

      formatter = forEachSystem (pkgs: pkgs.nixfmt);

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            # In case you're not on a NixOS system
            pkgs.nixos-rebuild

            pkgs.nixfmt
          ];
        };
      });
    };
}
