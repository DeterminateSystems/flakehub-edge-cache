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
  - [`flakehubEdgeCache.listen`](#flakehubedgecachelisten)
  - [`flakehubEdgeCache.cacheLifetime`](#flakehubedgecachecachelifetime)
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
This defaults to the systemd-resolved address, but nginx can be directed to use any DNS resolver (such as Google public DNS or one on an internal network).

### `flakehubEdgeCache.listen`

* Type: list of string
* Default: `["80" "[::]:80"]`.

Corresponds to the address(es) in nginx's [`listen` directive](https://nginx.org/en/docs/http/ngx_http_core_module.html#listen).
The `default_server` option is always set for each address.

### `flakehubEdgeCache.cacheLifetime`

* Type: string that matches nginx's duration types (a number ending in `d`, `h`, `m`, or `s`).
* Default: `"7d"`

When downloading a NAR, successful responses from FlakeHub cache (200, 301, or 302) will be kept in nginx's cache for this duration.
No other responses are cached.

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
