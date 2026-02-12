{ system, inputs }:
let
  inherit (inputs.self) nixosModules;
  inherit (inputs) nixpkgs determinate;

  pkgs = nixpkgs.legacyPackages.${system};
in
nixpkgs.lib.nixosSystem {
  inherit pkgs;

  modules = [
    determinate.nixosModules.default
    nixosModules.default

    (
      { pkgs, ... }:
      {
        system.stateVersion = "26.02";

        users.users.root.password = "password";
        services.getty.autologinUser = "root";

        users.mutableUsers = false;

        environment.systemPackages = with pkgs; [
          net-tools
          tree
          vim
        ];

        nix.settings = {
          substituters = [ "http://localhost/" ];

          netrc-file = [ "/root/netrc" ];
        };

        virtualisation.diskSize = 32 * 1024;
      }
    )

    {
      # Flex a few options
      config.flakehubEdgeCache = {
        enable = true;

        dnsResolvers = [
          "8.8.8.8"
          "8.8.4.4"
        ];

        keyZoneSize = "5m";

        minCacheFree = "512m";

        workerUserName = "fec-custom";
        workerGroupName = "fec-custom";

        tempDirectory = null;
      };
    }
  ];
}
