{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.flakehubEdgeCache;
  nginxConfiguration = import ./configuration.nix { inherit cfg lib pkgs; };
in
{
  options.flakehubEdgeCache = (
    (import ./options.nix { inherit lib; })
    // {
      enable = lib.mkEnableOption "FlakeHub edge Cache";
      nginx = lib.mkPackageOption pkgs "nginx" { };

      # not an option in minnows
      cacheDirectory = lib.mkOption {
        type = lib.types.path;
        default = "/var/flakehub-edge-cache";
        description = "Directory to use for the edge cache. Managed by systemd-tmpfiles.d.";
      };

      # not an option in minnows
      tempDirectory = lib.mkOption {
        type = with lib.types; nullOr path;
        default = "/tmp/flakehub-edge-cache";
        description = "Whether or not to store in-progress cache objects in a temporary directory. If null, nginx will only use its cache storage.";
      };

      # not an option in minnows
      workerUserName = lib.mkOption {
        type = lib.types.str;
        default = "flakehub-edge-cache";
        description = "Name for the user who will own the edge cache and run as the nginx worker";
      };

      # not an option in minnows
      workerGroupName = lib.mkOption {
        type = lib.types.str;
        default = "flakehub-edge-cache";
        description = "Name for the group who will own the edge cache and run as the nginx worker";
      };

      # different default than minnows
      sslTrustedCertificate = lib.mkOption {
        type = lib.types.str;
        default = "/etc/ssl/certs/ca-bundle.crt";
        description = ''
          Path to the CA bundle nginx should use when verifying FlakeHub Cache.
          The default is the standard NixOS CA bundle path; override it on systems
          that install the bundle elsewhere.
        '';
      };
    }
  );

  config = lib.mkIf cfg.enable {
    users.groups.flakehub-edge-cache = {
      name = cfg.workerGroupName;
    };

    users.users.flakehub-edge-cache = {
      name = cfg.workerUserName;
      group = cfg.workerGroupName;
      isSystemUser = true;
    };

    systemd.tmpfiles.settings.flakehub-edge-cache.${cfg.cacheDirectory}.d = {
      age = "-";
      user = cfg.workerUserName;
      group = cfg.workerGroupName;
      mode = "0750";
    };

    systemd.services.flakehub-edge-cache = {
      serviceConfig = {
        PrivateTmp = true;
        LogsDirectory = "nginx";
      };

      script = "${lib.getExe cfg.nginx} -c ${nginxConfiguration}";
    };
  };
}
