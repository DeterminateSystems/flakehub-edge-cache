{ lib }:

let
  nginxDurationType = lib.types.strMatching "^[0-9]+[dhms]$";
  nginxSizeType = lib.types.strMatching "^[0-9]+[kmg]$";
in
{
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

  extraLogFields = lib.mkOption {
    type = lib.types.str;
    default = "cache=$upstream_cache_status upstream_bytes=$upstream_bytes_received request_time=$request_time";
    description = ''
      Extra fields appended to the access log_format. The default adds the
      cache observability fields a pull-through cache needs; set to "" for
      the minimal format or replace it to suit your log pipeline.
    '';
  };

  sslVerify = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether nginx should verify the FlakeHub Cache TLS certificate.";
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

  upstreamResolveTimeout = lib.mkOption {
    type = lib.types.nullOr nginxDurationType;
    default = null;
    description = ''
      DNS resolution timeout for all upstream requests and connect timeout for
      the narinfo and NAR passthroughs to cache.flakehub.com. Null uses
      nginx's defaults.
    '';
  };

  upstreamReadTimeout = lib.mkOption {
    type = lib.types.nullOr nginxDurationType;
    default = null;
    description = ''
      Read/send timeout for the narinfo passthrough to cache.flakehub.com.
      Null uses nginx's default (60s). Deliberately narinfo-only: it bounds
      the gap between reads, so a tight value could abort slow but
      progressing NAR transfers.
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

}
