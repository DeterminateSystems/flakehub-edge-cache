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

      # Resolve the cache address per request so address changes do not require an nginx reload.
      resolver ${toString cfg.dnsResolvers} valid=5s ipv4=on ipv6=${
        if cfg.dnsResolverIPv6 then "on" else "off"
      };
      ${lib.optionalString (
        cfg.upstreamConnectTimeout != null
      ) "resolver_timeout ${cfg.upstreamConnectTimeout};"}

      location = /nix-cache-info {
        return 200 "WantMassQuery: 1\nStoreDir: /nix/store\nPriority: 30\n"; # Higher priority than FHC (39) and cache.nixos.org (40)
      }

      # Pass requests for narinfo directly to FlakeHub Cache, but never cache it
      location ~ /.*?\.narinfo$ {
        set $fhc_upstream https://cache.flakehub.com;
        proxy_pass $fhc_upstream;
        proxy_ssl_server_name on;
        proxy_ssl_name cache.flakehub.com;
        ${lib.optionalString cfg.sslVerify "proxy_ssl_verify on;"}
        ${lib.optionalString cfg.sslVerify "proxy_ssl_trusted_certificate \"${cfg.sslTrustedCertificate}\";"}
        ${lib.optionalString cfg.sslVerify "proxy_ssl_verify_depth ${toString cfg.sslVerifyDepth};"}
        proxy_set_header Host cache.flakehub.com;
        ${lib.optionalString (
          cfg.upstreamConnectTimeout != null
        ) "proxy_connect_timeout ${cfg.upstreamConnectTimeout};"}
        ${lib.optionalString (
          cfg.upstreamReadTimeout != null
        ) "proxy_read_timeout ${cfg.upstreamReadTimeout}; proxy_send_timeout ${cfg.upstreamReadTimeout};"}
        ${lib.optionalString cfg.narinfoMissOnError "proxy_intercept_errors on; error_page 408 502 503 504 = @narinfo_miss;"}
      }
      ${lib.optionalString cfg.narinfoMissOnError ''
        # A 404 here is a clean cache miss to Nix; a 5xx/timeout is not.
        location @narinfo_miss {
          add_header X-FEC-Miss-Reason $upstream_status always;
          return 404;
        }''}

      # Allow caching of any request for a NAR
      location /nar {
        proxy_cache fhc;
        proxy_cache_valid ${cfg.cacheLifetime};
        ${lib.optionalString cfg.cacheLock "proxy_cache_lock on; proxy_cache_lock_timeout ${cfg.cacheLockTimeout}; proxy_cache_lock_age ${cfg.cacheLockAge};"}

        set $fhc_upstream https://cache.flakehub.com;
        proxy_pass $fhc_upstream;
        proxy_ssl_server_name on;
        proxy_ssl_name cache.flakehub.com;
        ${lib.optionalString cfg.sslVerify "proxy_ssl_verify on;"}
        ${lib.optionalString cfg.sslVerify "proxy_ssl_trusted_certificate \"${cfg.sslTrustedCertificate}\";"}
        ${lib.optionalString cfg.sslVerify "proxy_ssl_verify_depth ${toString cfg.sslVerifyDepth};"}
        proxy_set_header Host cache.flakehub.com;
      }
    }
  '';

  nginxConfiguration = builtins.toFile "fhc-edge-nginx.conf" ''
    error_log ${cfg.errorLog};

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
                        '"$http_user_agent" "$http_x_forwarded_for"${
                          lib.optionalString (cfg.extraLogFields != "") " ${cfg.extraLogFields}"
                        } upstream_status=$upstream_status upstream_addr=$upstream_addr upstream_connect_time=$upstream_connect_time';

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
        ${lib.optionalString (cfg.cacheInactive != null) "inactive=${cfg.cacheInactive}"}
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

    dnsResolverIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether nginx should request IPv6 addresses when resolving cache.flakehub.com.";
    };

    listen = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "80"
        "[::]:80"
      ];
      description = "Listen directive for nginx. All servers are given as the default server.";
    };

    extraLogFields = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "cache=$upstream_cache_status upstream_bytes=$upstream_bytes_received request_time=$request_time";
      description = ''
        Extra fields appended to the access log_format. A pull-through cache
        needs $upstream_cache_status (and friends) for observability, but the
        default format omits them.
      '';
    };

    errorLog = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/nginx/error.log";
      example = "stderr";
      description = ''
        Destination for nginx's error log. Set to stderr to send errors through
        the service manager's standard error stream for journal-based log
        collection.
      '';
    };

    sslVerify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether nginx should verify the FlakeHub Cache TLS certificate.";
    };

    sslTrustedCertificate = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssl/certs/ca-bundle.crt";
      description = ''
        Path to the CA bundle nginx should use when verifying FlakeHub Cache.
        The default is the standard NixOS CA bundle path; override it on systems
        that install the bundle elsewhere.
      '';
    };

    sslVerifyDepth = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Maximum verification depth for the FlakeHub Cache TLS certificate chain.";
    };

    cacheLifetime = lib.mkOption {
      type = nginxDurationType;
      default = "7d";
      description = "Lifetime in nginx's cache for successful responses.";
    };

    cacheInactive = lib.mkOption {
      type = lib.types.nullOr nginxDurationType;
      default = null;
      description = ''
        Sets proxy_cache_path inactive=: how long a cached object may go
        unaccessed before nginx evicts it, independent of freshness. Defaults to
        null, leaving nginx's own default (10 minutes). nginx evicts the working
        set between bursts of traffic at that default, so a bursty pull-through
        cache of immutable NARs typically wants this set to cacheLifetime.
      '';
    };

    upstreamConnectTimeout = lib.mkOption {
      type = lib.types.nullOr nginxDurationType;
      default = null;
      description = ''
        DNS resolution timeout for all upstream requests and connect timeout for
        the narinfo passthrough to cache.flakehub.com. Null uses nginx's
        defaults.
      '';
    };

    upstreamReadTimeout = lib.mkOption {
      type = lib.types.nullOr nginxDurationType;
      default = null;
      description = ''
        Read/send timeout for the narinfo passthrough to cache.flakehub.com.
        Null uses nginx's default (60s). Pair with narinfoMissOnError so a slow
        origin becomes a clean miss rather than a 504 surfaced to the client.
      '';
    };

    narinfoMissOnError = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Translate an upstream narinfo failure (408/502/503/504) into a 404. Nix
        treats 404 as a miss and falls through to its other substituters,
        whereas a 5xx/timeout is a hard error it can fail the build on.
      '';
    };

    cacheLock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable proxy_cache_lock for NAR requests so concurrent requests for the
        same uncached NAR don't all stampede the origin; only the first
        populates the cache and the rest wait for it.
      '';
    };

    cacheLockTimeout = lib.mkOption {
      type = nginxDurationType;
      default = "5s";
      description = ''
        proxy_cache_lock_timeout: how long a request waits on the lock before
        fetching from the origin itself. Raise above your slowest NAR fetch or
        waiters will stampede anyway.
      '';
    };

    cacheLockAge = lib.mkOption {
      type = nginxDurationType;
      default = "5s";
      description = ''
        proxy_cache_lock_age: if the populating request runs longer than this,
        another request is allowed to the origin. Raise alongside
        cacheLockTimeout above your slowest NAR fetch.
      '';
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
