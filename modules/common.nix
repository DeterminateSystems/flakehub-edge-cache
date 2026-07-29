{ cfg, lib }:

{
  nixosConfiguration = builtins.toFile "fhc-edge-nginx.conf" ''
    error_log stderr;

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

      server {
        ${lib.concatMapStringsSep "\n  " (addr: "listen ${addr} default_server;") cfg.listen}

        # Ignored by nginx since we're using default_server for our listening
        server_name _;

        # Resolve the cache address per request so address changes do not require an nginx reload.
        resolver ${toString cfg.dnsResolvers} valid=5s ipv4=on ipv6=${
          if cfg.dnsResolverIPv6 then "on" else "off"
        };
        ${lib.optionalString (
          cfg.upstreamResolveTimeout != null
        ) "resolver_timeout ${cfg.upstreamResolveTimeout};"}

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
            cfg.upstreamResolveTimeout != null
          ) "proxy_connect_timeout ${cfg.upstreamResolveTimeout};"}
          ${lib.optionalString (
            cfg.upstreamReadTimeout != null
          ) "proxy_read_timeout ${cfg.upstreamReadTimeout}; proxy_send_timeout ${cfg.upstreamReadTimeout};"}
        }

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
          ${lib.optionalString (
            cfg.upstreamResolveTimeout != null
          ) "proxy_connect_timeout ${cfg.upstreamResolveTimeout};"}
        }
      }
    }
  '';
}
