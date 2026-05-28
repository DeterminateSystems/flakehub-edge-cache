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
    docs = ./README.md;

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
  };

  interface =
    let
      nginxDurationType = flow.lib.types.strMatching "^[0-9]+[dhms]$";
      nginxSizeType = flow.lib.types.strMatching "^[0-9]+[kmg]$";
    in
    {
      nginx = {
        description = "Which `nginx` package to use for the local cache server.";
        type = flow.lib.types.package;
      };

      dnsResolvers = {
        description = "List of IP addresses for nginx to use when resolving the cache.flakehub.com address.";
        type = flow.lib.types.listOf flow.lib.types.str;
        default = [ "127.0.0.1" ];
      };

      listen = {
        description = "Listen directive for nginx. All servers are given as the default server.";
        type = flow.lib.types.listOf flow.lib.types.str;
        default = [
          "80"
          "[::]:80"
        ];
      };

      cacheLifetime = {
        description = "Lifetime in nginx's cache for successful responses.";
        type = nginxDurationType;
        default = "7d";
      };

      keyZoneSize = {
        description = ''Maximum size of the key zone. Per the nginx docs: "One megabyte zone can store about 8 thousand keys."'';
        type = nginxSizeType;
        default = "10m";
      };

      minCacheFree = {
        description = "Minimum amount of free space for nginx to reserve in the file system on which the cache resides.";
        type = nginxSizeType;
        default = "1g";
      };

      maxCacheSize = {
        description = "Maximum size for nginx's cache on the file system.";
        type = flow.lib.types.nullOr nginxSizeType;
        default = null;
      };

      cacheDirectory = {
        description = "Directory to use for the edge cache. Created (and chowned to the user/group resources) on service start.";
        type = flow.lib.types.path;
        default = "/var/flakehub-edge-cache";
      };

      # tempDirectory = {
      #   description = "Whether or not to store in-progress cache objects in a temporary directory. If null, nginx will only use its cache storage.";
      #   type = flow.lib.types.nullOr flow.lib.types.path;
      #   default = "/tmp/flakehub-edge-cache";
      # };
    };

  implementation =
    {
      this,
      flowContext,
      pkgs,
      resources,
      ...
    }:
    let
      inherit (resources.users) user;
      inherit (resources.groups) group;
      inherit (pkgs) lib;

      edgeConfiguration = builtins.toFile "fhc-edge.conf" ''
        server {
          ${lib.concatMapStringsSep "\n  " (addr: "listen ${addr} default_server;") this.listen}

          # Ignored by nginx since we're using default_server for our listening
          server_name _;

          # Allow nginx to do DNS resolution of the cache address
          resolver ${toString this.dnsResolvers} valid=5s ipv4=on ipv6=on;

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
            proxy_cache_valid ${this.cacheLifetime};

            proxy_pass https://cache.flakehub.com;
          }
        }
      '';

      nginxConfiguration = builtins.toFile "fhc-edge-nginx.conf" ''
        error_log ${flowContext.stateDir}/error.log;

        # Run workers under the edge cache user
        user ${user.name};

        worker_processes auto;

        pid ${flowContext.stateDir}/nginx.pid;
        daemon off;

        events {
          worker_connections 1024;
        }

        http {
          default_type application/octet-stream;

          log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                            '$status $body_bytes_sent "$http_referer" '
                            '"$http_user_agent" "$http_x_forwarded_for"';

          access_log  ${flowContext.stateDir}/access.log main;
          error_log  ${flowContext.stateDir}/error.log main;

          sendfile        on;
          #tcp_nopush     on;

          keepalive_timeout  65;

          proxy_cache_path
            ${this.cacheDirectory}
            levels=1:2
            keys_zone=fhc:${this.keyZoneSize}
            ${lib.optionalString (this.maxCacheSize != null) "max_size=${this.maxCacheSize}"}
            ${lib.optionalString (this.minCacheFree != null) "min_free=${this.minCacheFree}"}
            ;

          include ${edgeConfiguration};
        }
      '';

      preStartScriptRoot = pkgs.writeShellScript "fhc-edge-cache-prestart-root" ''
        set -e
        ${pkgs.coreutils}/bin/install -d \
          -o ${user.name} -g ${group.name} -m 0750 \
          ${this.cacheDirectory}
      '';
    in
    {
      systemd.services.flakehub-edge-cache = {
        Service.ExecStartPre = [
          "+${pkgs.bash}/bin/sh ${preStartScriptRoot}"
        ];
        Service.ExecStart = "${lib.getExe this.nginx} -c ${nginxConfiguration}";
      };
    };
}
