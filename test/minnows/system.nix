{ inputs, system }:

inputs.minnows.lib.minnowsSystem {
  inherit system;

  metadata = {
    name = "demo-machine";
    description = "Minnows is cool!";
    flakeref = "demo-machine";
    attributes = {
      role = "demo";
    };
    tags = [
      "sample"
      "demo"
    ];
  };

  platforms = {
    "demo-qemu" = {
      definition = inputs.minnows-platform-qemu.minnowsPlatforms.default;
    };
  };

  resources = {
    users.hello-minnows = {
      uid = 7;
    };

    groups.hello-minnows = {
      gid = 7;
    };

    devices.console = {
      path = "/dev/console";
    };

    listeningPorts.ssh = {
      family = null;
      protocol = "tcp";
      port = 22;
    };
  };

  flows.fec1 = {
    definition = import ../flow.nix { inherit inputs system; };
    config = { };
    resources = {
      users.user = "hello-minnows";
      groups.group = "hello-minnows";
    };
  };

  flows.debug-shell = {
    definition = inputs.minnows-flow-debug-shell.minnowsFlows.default;
    config = {
      shell = "${inputs.nixpkgs.legacyPackages.${system}.bashInteractive}/bin/bash";
      packages = with inputs.nixpkgs.legacyPackages.${system}; [
        busybox
        gnugrep
        gnused
        kmod
        lshw
        nano
        ripgrep
        systemd
        util-linux
        vim
      ];
    };

    resources = {
      devices.console = "console";
    };

    grantAll = true;
  };
}
