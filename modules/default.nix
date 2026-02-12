{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.flakehubEdgeCache;

  nginxDurationType = lib.types.strMatching "^[0-9]+[dhms]$";
  nginxSizeType = lib.types.strMatching "^[0-9]+[kmg]$";

  edgeConfiguration = builtins.toFile "fhc-edge.conf" ''
    server {
      ${lib.concatMapStringsSep "\n  " (addr: "listen ${addr} default_server;") cfg.listen}

      # Ignored by nginx since we're using default_server for our listening
      server_name _;

      # Allow nginx to do DNS resolution of the cache address
      resolver ${toString cfg.dnsResolvers} valid=5s ipv4=on ipv6=on;

      location = /nix-cache-info {
        return 200 "WantMassQuery: 1\nStoreDir: /nix/store\nPriority: 30\n"; # Higher priority than FHC (39) and cache.nixos.org (40)
      }

      # Pass requests for narinfo directly to FlakeHub Cache, but never cache it
      location ~ /.*?\.narinfo$ {
        proxy_pass https://cache.flakehub.com;
      }

      # Allow caching of any request for a NAR
      location /nar {
        proxy_cache fhc;
        proxy_cache_valid ${cfg.cacheLifetime};

        proxy_pass https://cache.flakehub.com;
      }
    }
  '';

  nginxConfiguration = builtins.toFile "fhc-edge-nginx.conf" ''
    error_log /var/log/nginx/error.log;

    # Run workers under the edge cache user
    user ${cfg.workerUserName};

    worker_processes auto;

    pid /run/nginx.pid;
    daemon off;

    events {
      worker_connections 1024;
    }

    http {
      default_type application/octet-stream;

      log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';

      access_log  /var/log/nginx/access.log main;

      sendfile        on;
      #tcp_nopush     on;

      keepalive_timeout  65;

      ${lib.optionalString (cfg.tempDirectory != null) "proxy_temp_path ${cfg.tempDirectory} 1 2;"}
      proxy_cache_path
        ${cfg.cacheDirectory}
        levels=1:2
        use_temp_path=${if cfg.tempDirectory != null then "on" else "off"}
        keys_zone=fhc:${cfg.keyZoneSize}
        ${lib.optionalString (cfg.maxCacheSize != null) "max_size=${cfg.maxCacheSize}"}
        ${lib.optionalString (cfg.minCacheFree != null) "min_free=${cfg.minCacheFree}"}
        ;

      include ${edgeConfiguration};
    }
  '';
in
{
  options.flakehubEdgeCache = {
    enable = lib.mkEnableOption "FlakeHub edge Cache";

    nginx = lib.mkPackageOption pkgs "nginx" { };

    dnsResolvers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "127.0.0.1" ];
      description = "List of IP addresses for nginx to use when resolving the cache.flakehub.com address.";
    };

    listen = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "80"
        "[::]:80"
      ];
      description = "Listen directive for nginx. All servers are given as the default server.";
    };

    cacheLifetime = lib.mkOption {
      type = nginxDurationType;
      default = "7d";
      description = "Lifetime in nginx's cache for successful responses.";
    };

    keyZoneSize = lib.mkOption {
      type = nginxSizeType;
      default = "10m";
      description = ''Maximum size of the key zone. Per the nginx docs: "One megabyte zone can store about 8 thousand keys."'';
    };

    minCacheFree = lib.mkOption {
      type = nginxSizeType;
      default = "1g";
      description = "Minimum amount of free space for nginx to reserve in the file system on which the cache resides.";
    };

    maxCacheSize = lib.mkOption {
      type = lib.types.nullOr nginxSizeType;
      default = null;
      description = "Maximum size for nginx's cache on the file system.";
    };

    cacheDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/var/flakehub-edge-cache";
      description = "Directory to use for the edge cache. Managed by systemd-tmpfiles.d.";
    };

    tempDirectory = lib.mkOption {
      type = with lib.types; nullOr path;
      default = "/tmp/flakehub-edge-cache";
      description = "Whether or not to store in-progress cache objects in a temporary directory. If null, nginx will only use its cache storage.";
    };

    workerUserName = lib.mkOption {
      type = lib.types.str;
      default = "flakehub-edge-cache";
      description = "Name for the user who will own the edge cache and run as the nginx worker";
    };

    workerGroupName = lib.mkOption {
      type = lib.types.str;
      default = "flakehub-edge-cache";
      description = "Name for the group who will own the edge cache and run as the nginx worker";
    };
  };

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
