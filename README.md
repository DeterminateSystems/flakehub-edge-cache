# FlakeHub Edge Cache

## Table of Contents

- [Table of Contents](#table-of-contents)
- [Behavior](#behavior)
  - [Caveats](#caveats)
- [Files](#files)
- [Options](#options)
  - [`flakehubEdgeCache.enable`](#flakehubedgecacheenable)
  - [`flakehubEdgeCache.nginx`](#flakehubedgecachenginx)
  - [`flakehubEdgeCache.dnsResolvers`](#flakehubedgecachednsresolvers)
  - [`flakehubEdgeCache.dnsResolverIPv6`](#flakehubedgecachednsresolveripv6)
  - [`flakehubEdgeCache.listen`](#flakehubedgecachelisten)
  - [`flakehubEdgeCache.extraLogFields`](#flakehubedgecacheextralogfields)
  - [`flakehubEdgeCache.sslVerify`](#flakehubedgecachesslverify)
  - [`flakehubEdgeCache.sslTrustedCertificate`](#flakehubedgecachessltrustedcertificate)
  - [`flakehubEdgeCache.sslVerifyDepth`](#flakehubedgecachesslverifydepth)
  - [`flakehubEdgeCache.cacheLifetime`](#flakehubedgecachecachelifetime)
  - [`flakehubEdgeCache.cacheInactive`](#flakehubedgecachecacheinactive)
  - [`flakehubEdgeCache.upstreamResolveTimeout`](#flakehubedgecacheupstreamresolvetimeout)
  - [`flakehubEdgeCache.upstreamReadTimeout`](#flakehubedgecacheupstreamreadtimeout)
  - [`flakehubEdgeCache.cacheLock`](#flakehubedgecachecachelock)
  - [`flakehubEdgeCache.cacheLockTimeout`](#flakehubedgecachecachelocktimeout)
  - [`flakehubEdgeCache.cacheLockAge`](#flakehubedgecachecachelockage)
  - [`flakehubEdgeCache.keyZoneSize`](#flakehubedgecachekeyzonesize)
  - [`flakehubEdgeCache.minCacheFree`](#flakehubedgecachemincachefree)
  - [`flakehubEdgeCache.maxCacheSize`](#flakehubedgecachemaxcachesize)
  - [`flakehubEdgeCache.cacheDirectory`](#flakehubedgecachecachedirectory)
  - [`flakehubEdgeCache.tempCacheDirectory`](#flakehubedgecachetempcachedirectory)
  - [`flakehubEdgeCache.workerUserName`](#flakehubedgecacheworkerusername)
  - [`flakehubEdgeCache.workerGroupName`](#flakehubedgecacheworkergroupname)

## Behavior

This is a simple implementation of a network-local cache for FlakeHub Cache. The behavior is like so:

* Requests for `/nix-cache-info` return a fixed info.
* Requests for `/*.narinfo` are passed directly through to FlakeHub Cache and never cached.
  This prevents inadvertent leaks of derivation metadata (such as the reference graph).
* Requests for `nar/*` are cached when successful.

Note that, except for the first case, requests to this service must be authenticated by users.
It does not do any authentication on its own.

The use case here is either as a pull-through cache (Nix uses it as the sole substituter) or as a lookaside cache (Nix races both it and FlakeHub Cache).

### Caveats

1. This cache, by design, bypasses some of the access control features of FlakeHub Cache: users who know a NAR path can potentially download a NAR without authentication.
   (However, they cannot retrieve the narinfo.)
2. Anyone with direct access to this service's file system have direct access to cached NAR responses.

## Files

* `modules/default.nix`: The implementation of the cache as a NixOS module. This is exposed in the flake as `nixosModules.default`.
* `test/vm.nix`: A small QEMU-powered test VM. This can also double as example usage.

## Options

### `flakehubEdgeCache.enable`

* Type: boolean
* Default: `false`

Boolean option to turn on the local cache.

### `flakehubEdgeCache.nginx`

* Type: package
* Default: `pkgs.nginx`

Which `nginx` package to use for the local cache server.

### `flakehubEdgeCache.dnsResolvers`

* Type: list of string
* Default: `["127.0.0.1"]`

For nginx's proxy logic to work, DNS resolvers are required.
This defaults to localhost, but nginx can be directed to use any DNS resolver (such as Google public DNS or one on an internal network).
Ensure that a resolver is listening at one of the configured addresses; nginx uses these resolvers for each request instead of resolving FlakeHub Cache only when it starts.

### `flakehubEdgeCache.dnsResolverIPv6`

* Type: boolean
* Default: `true`

Whether nginx requests IPv6 addresses when resolving FlakeHub Cache.
Disable this when the cache host has no working IPv6 route.

### `flakehubEdgeCache.listen`

* Type: list of string
* Default: `["80" "[::]:80"]`.

Corresponds to the address(es) in nginx's [`listen` directive](https://nginx.org/en/docs/http/ngx_http_core_module.html#listen).
The `default_server` option is always set for each address.

### `flakehubEdgeCache.extraLogFields`

* Type: string
* Default: `"cache=$upstream_cache_status upstream_bytes=$upstream_bytes_received request_time=$request_time"`

Extra fields appended to nginx's access `log_format`.
The default adds the cache observability fields a pull-through cache needs for hit-ratio and egress metrics; set it to `""` for the minimal format or replace it to suit your log pipeline.
The format always includes `upstream_status=$upstream_status`, `upstream_addr=$upstream_addr`, and `upstream_connect_time=$upstream_connect_time` so upstream failures and connection attempts remain visible when nginx returns a different response to the client.

### `flakehubEdgeCache.sslVerify`

* Type: boolean
* Default: `true`

Whether nginx verifies the FlakeHub Cache TLS certificate.
When enabled, nginx uses `sslTrustedCertificate` and `sslVerifyDepth` for verification.

### `flakehubEdgeCache.sslTrustedCertificate`

* Type: string
* Default: `"/etc/ssl/certs/ca-bundle.crt"`

The CA bundle nginx uses to verify FlakeHub Cache.
The default is the standard NixOS CA bundle path; override it on systems that install the bundle elsewhere.

### `flakehubEdgeCache.sslVerifyDepth`

* Type: positive integer
* Default: `2`

The maximum verification depth for the FlakeHub Cache TLS certificate chain.

### `flakehubEdgeCache.cacheLifetime`

* Type: string that matches nginx's duration types (a number ending in `d`, `h`, `m`, or `s`).
* Default: `"7d"`

When downloading a NAR, successful responses from FlakeHub cache (200, 301, or 302) will be kept in nginx's cache for this duration.
No other responses are cached.

### `flakehubEdgeCache.cacheInactive`

* Type: nullable string that matches nginx's duration types.
* Default: `null`

Sets the [`inactive=`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path) parameter on `proxy_cache_path`: a cached object not *accessed* within this duration is evicted regardless of its freshness.
When `null` (the default), nginx uses its own default of 10 minutes, which evicts the working set between bursts of traffic.
Since NAR content is immutable, a bursty pull-through cache typically wants this set to `cacheLifetime`.
Note that lengthening retention lets the cache grow larger, so set [`maxCacheSize`](#flakehubedgecachemaxcachesize) accordingly.

### `flakehubEdgeCache.upstreamResolveTimeout`

* Type: nullable string that matches nginx's duration types.
* Default: `null`

If non-null, sets `resolver_timeout` for all upstream requests and `proxy_connect_timeout` on the narinfo and NAR passthroughs to FlakeHub Cache.
`null` uses nginx's defaults.

### `flakehubEdgeCache.upstreamReadTimeout`

* Type: nullable string that matches nginx's duration types.
* Default: `null`

If non-null, sets `proxy_read_timeout` and `proxy_send_timeout` on the narinfo passthrough to FlakeHub Cache.
`null` uses nginx's default (60s).
Deliberately narinfo-only: it bounds the gap between successive reads, so a tight value could abort slow but progressing NAR transfers.

### `flakehubEdgeCache.cacheLock`

* Type: boolean
* Default: `false`

When true, enables [`proxy_cache_lock`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_lock) for NAR requests, so concurrent requests for the same uncached NAR don't all stampede FlakeHub Cache: only the first populates the cache and the rest wait for it.

### `flakehubEdgeCache.cacheLockTimeout`

* Type: string that matches nginx's duration types.
* Default: `"5s"`

Sets [`proxy_cache_lock_timeout`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_lock_timeout): how long a request waits on the lock before fetching from the origin itself.
Only applies when [`cacheLock`](#flakehubedgecachecachelock) is enabled.
Raise this above your slowest NAR fetch, or waiters will stampede the origin anyway (nginx's default is 5s).

### `flakehubEdgeCache.cacheLockAge`

* Type: string that matches nginx's duration types.
* Default: `"5s"`

Sets [`proxy_cache_lock_age`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_lock_age): if the request populating the cache runs longer than this, another request is allowed through to the origin.
Only applies when [`cacheLock`](#flakehubedgecachecachelock) is enabled.
Raise this alongside `cacheLockTimeout`.

### `flakehubEdgeCache.keyZoneSize`

* Type: string that matches nginx's size types (a number ending in `k`, `m`, or `g`).
* Default: `"10m"`

The size of the key zone. The nginx documentation says that a one-megabyte zone can store about eight thousand keys, so the default here (ten megabytes) is probably generous enough, but this can be increased as large as necessary.

### `flakehubEdgeCache.minCacheFree`

* Type: nullable string that matches nginx's size types (a number ending in `k`, `m`, or `g`).
* Default: `"1g"`

If non-null, nginx's cache manager will attempt to reserve this much space in the file system on which the cache resides.

### `flakehubEdgeCache.maxCacheSize`

* Type: nullable string that matches nginx's size types (a number ending in `k`, `m`, or `g`).
* Default: `null`

If non-null, nginx's cache manager process will attempt to keep the cache within this size limit on the file system.

### `flakehubEdgeCache.cacheDirectory`

* Type: path
* Default: `/var/fhc-local-cache`

Directory to store cached NAR responses.
This directory is automatically created by `systemd-tmpfiles` to ensure the correct user/group ownership and mode (`0750`).

### `flakehubEdgeCache.tempCacheDirectory`

* Type: nullable path
* Default: `/tmp/fhc-local-cache`

If non-null, nginx will buffer downloads into a directory separate from the cache.
Note that the service always has `PrivateTmp=true;` set in its service configuration, so paths in `/tmp` may be stored on tmpfs.
When null, nginx will store downloads directly in the directory named by `cacheDirectory`.

### `flakehubEdgeCache.workerUserName`

* Type: string
* Default: `"fhc-local-cache"`

The nginx master process runs as root, but its worker processes will run under this user, which also owns the cache directory.
The user is created by the module as a system user and will be a member of the [worker group](#flakehubedgecacheworkergroupname).

### `flakehubEdgeCache.workerGroupName`

* Type: string
* Default: `"fhc-local-cache"`

The group that owns the local cache. The cache worker user should be the sole member of this group.
