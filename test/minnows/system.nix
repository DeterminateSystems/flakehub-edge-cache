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
    "demo-enable-debug" = {
      definition = {
        id = "enable-debug";
        description = "enable-debug";
        docs = "enable-debug";
        include = {
          minnows.debug = true;
        };
        mkBootspecOutputs = _: { };
      };
    };
  };

  resources = {
    users.hello-minnows = {
      uid = 101;
    };

    groups.hello-minnows = {
      gid = 101;
    };

    devices.console = {
      path = "/dev/console";
    };

    listeningPorts.ssh = {
      family = null;
      protocol = "tcp";
      port = 22;
    };

    listeningPorts.http = {
      family = null;
      protocol = "tcp";
      port = 80;
    };
  };

  flows.fec1 = {
    definition = import ../../flow.nix { inherit inputs; };
    config = {
      nginx = inputs.nixpkgs.legacyPackages.${system}.nginx;
      # dnsResolvers = [ "1.1.1.1" ];
    };
    grantedCapabilities.runAsRoot = true;
    grantedCapabilities.fullFilesystemAccess = true;
    resources = {
      users.user = "hello-minnows";
      groups.group = "hello-minnows";
      listeningPorts.listeningPort = "http";
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
