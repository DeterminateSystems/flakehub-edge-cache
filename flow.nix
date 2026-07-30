{ inputs }:

{ flow }:

flow.new {
  about = {
    name = "DeterminateSystems/flakehub-edge-cache";
    description = "Run a minimal FlakeHub Cache instance at the edge";
    flakeref = "https://flakehub.com/f/DeterminateSystems/minnows-flow-flakehub-edge-cache/0.1";
    tags = [
      "flakehub"
      "cache"
      "flakehub-edge"
    ];

    docs = "FEC is Fully Excellent (and) Cool";

    examples = [ ];
  };

  capabilities = {
    # nginx master process needs root in order to bind to privileged ports
    # and to spawn workers as the unprivileged worker user.
    requiredCapabilities.runAsRoot = true;

    # nginx needs to read/write the cache directory and (optionally) the
    # temp directory used for in-progress downloads.
    requiredCapabilities.fullFilesystemAccess = true;
  };

  resources = {
    users.user = {
      description = "User under which the nginx workers run and that owns the cache directory";
      example = "flakehub-edge-cache";
    };

    groups.group = {
      description = "Group that owns the cache directory";
      example = "flakehub-edge-cache";
    };

    listeningPorts.listeningPort = {
      description = "Port on which nginx accepts incoming cache requests.";
      example = {
        family = null;
        protocol = "tcp";
        port = 80;
      };
    };
  };

  interface = (import ./modules/options.nix { lib = flow.lib; }) // {
    nginx = {
      description = "Which `nginx` package to use for the local cache server.";
      type = flow.lib.types.package;
    };

    # different default than minnows
    # TODO: not sure how to do this without pkgs/system
    # sslTrustedCertificate = flow.lib.mkOption {
    #   type = flow.lib.types.string;
    #   default = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    #   description = ''
    #     Path to the CA bundle nginx should use when verifying FlakeHub Cache.
    #     The default is the standard NixOS CA bundle path; override it on systems
    #     that install the bundle elsewhere.
    #   '';
    # };
  };

  implementation =
    {
      this,
      flowContext,
      resources,
      ...
    }@impl:
    let
      pkgs = import inputs.nixpkgs {
        system = impl.pkgs.system;
      };
      inherit (resources.users) user;
      inherit (resources.groups) group;
      inherit (resources.listeningPorts) listeningPort;
      inherit (pkgs) lib;

      cfg = this // {
        listen = listenAddrs;
        cacheDirectory = "${flowContext.stateDir}/cache-state";
        tempDirectory = "${flowContext.stateDir}/cache-state-tmp";
        workerUserName = user.name;
        workerGroupName = group.name;
        sslTrustedCertificate = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
      nginxConfiguration = import ./modules/configuration.nix { inherit pkgs cfg lib; };

      listenAddrs =
        let
          port = toString listeningPort.port;
        in
        if listeningPort.family == "ipv6" then
          [ "[::]:${port}" ]
        else if listeningPort.family == "ipv4" then
          [ port ]
        else
          [
            port
            "[::]:${port}"
          ];

      preStartScriptRoot = pkgs.writeShellScript "fhc-edge-cache-prestart-root" ''
        set -e
        ${pkgs.coreutils}/bin/install -d \
          -o ${cfg.workerUserName} -g ${cfg.workerGroupName} -m 0750 \
          ${cfg.cacheDirectory}
      '';

      startScript = pkgs.writeShellScript "start-nginx.sh" ''
        set -x

        # TODO: terrible, but I need it for systemd-network-wait-online issues
        sleep 10

        ${lib.getExe this.nginx} -e stderr -c "${nginxConfiguration}"
      '';
    in
    {
      systemd.services.flakehub-edge-cache = {
        Service = {
          ExecStartPre = [
            "+${pkgs.bash}/bin/sh ${preStartScriptRoot}"
          ];
          ExecStart = "${pkgs.bash}/bin/sh ${startScript}";
          Restart = "no";
        };
        Unit = {
          After = [
            "network.target"
            "dbus.service"
            "network-online.target"
          ];
          Wants = [
            "network-online.target"
          ];
        };
      };
    };
}
