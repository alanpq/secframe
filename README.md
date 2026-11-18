# secureframe-agent-flake
NixOS module for easily running Secureframe Agent

## Getting started
Add this flake as an input:
```nix
# flake.nix
{
    inputs = {
        # ...
        secureframe-agent.url = "github:alanpq/secureframe-agent-flake";
        secureframe-agent.inputs.nixpkgs.follows = "nixpkgs"; # optional
    };
}
```

Import the NixOS module:
```nix
imports = [inputs.secureframe-agent.nixosModules.default];
```

Configure the secureframe-agent service (see [Extracting enrollment configuration](#extracting-enrollment-configuration) & [Module options](#module-options)):
```nix

    services.secureframe-agent = {
      enable = true;

      hostIdentifier = "...";
      enrollSecretFile = "...";

      desktop.enable = true;
    };
```

### Extracting enrollment configuration

Secureframe provide per-user binaries, with the relevant enrollment credentials bundled. You can extract them for use in this module by using `nix run .#read-deb ./secureframe-agent.deb`.

> [!NOTE]
> Make sure to download the Secureframe Agent for Debian Linux (`.deb`)

## Module options

All options live under `services.secureframe-agent`. Only `enable` and `enrollSecretFile` are required; `hostIdentifier` should normally be set to the value printed by `read-deb`.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enable` | bool | `false` | Run the agent as the `secureframe-agent` systemd service. |
| `enrollSecretFile` | path | *(required)* | File containing the enroll secret. |
| `hostIdentifier` | null or string | `null` | Secureframe host identifier passed to osquery. |
| `fleetUrl` | string | `"https://agent.secureframe.com:443"` | Secureframe (Fleet) server to enroll against. |
| `orbit.package` | package | `pkgs.fleet-orbit` | Fleet orbit package. |
| `orbit.extraArgs` | list of string | `[]` | Extra orbit flags. |
| `osquery.package` | package | `pkgs.osquery` | osquery package; provides `osqueryd`. |
| `osquery.extraArgs` | list of string | `[]` | Extra osquery flags. |
| `desktop.enable` | bool | `false` | Launch Fleet Desktop (systray). |
| `desktop.package` | package | `pkgs.fleet-desktop` | Fleet Desktop package. |
| `dataDir` | path | `"/var/lib/orbit"` | Orbit/osquery runtime state. |
| `logDir` | path | `"/var/log/orbit/"` | Orbit/osquery logs. |
| `debug` | bool | `false` | Orbit debug logging. |
| `insecure` | bool | `false` | Disable TLS certificate verification. |

### `enrollSecretFile`

Path to a file whose content is the enroll secret (the `enroll secret` line from `read-deb`). The file is read at service start through systemd `LoadCredential`, so it never enters the Nix store; point it at a secret managed by e.g. sops-nix or agenix (`/run/secrets/secureframe-enroll`).

### `hostIdentifier`

When set, osquery is started with `--host_identifier specified --specified_identifier <value>`, matching the vendor package. When `null`, orbit falls back to its default UUID-based host identification.

### `fleetUrl`

Exported to orbit as `ORBIT_FLEET_URL`. Only change it if `read-deb` reports a different URL.

### `orbit.package` / `orbit.extraArgs`

The orbit binary run by the service. `extraArgs` are appended to the orbit command line, before the `--` that separates orbit flags from osquery flags.

### `osquery.package` / `osquery.extraArgs`

orbit runs `osqueryd` from `osquery.package` instead of downloading its own. `extraArgs` are passed to osquery after `--`, following the `hostIdentifier` flags. Use it for any remaining osquery flags reported by `read-deb` under `osquery.extraArgs`.

### `desktop.enable` / `desktop.package`

Starts Fleet Desktop, the systray companion app. It requires a graphical session and GTK/WebKit libraries; leave it disabled on headless servers. `desktop.package` is only used when `desktop.enable` is `true`.

### `dataDir` / `logDir`

- `dataDir`: orbit root directory and working directory; the osquery database is `<dataDir>/osquery.db`.
- `logDir`: orbit logs to `<logDir>/orbit/orbit.log`, osquery to `<logDir>/osquery/`.

> [!NOTE]
> The service only has systemd create `/var/lib/orbit` and `/var/log/orbit`. If you move either directory elsewhere, make sure it exists and is writable by root.

### `debug` / `insecure`

- `debug`: enables orbit debug logging (`ORBIT_DEBUG`).
- `insecure`: disables TLS certificate verification (`ORBIT_INSECURE`). For testing only.

### Fixed behaviour

The following are always set by the module and cannot be configured:

- Orbit auto-updates are disabled (`ORBIT_DISABLE_UPDATES=true`); upgrade the agent by updating the packages, e.g. through `nixpkgs`.
- The orbit keystore is disabled (`ORBIT_DISABLE_KEYSTORE=true`).
- The service runs as `root` (osquery needs root to read system tables), restarts every 10 s on exit, and is limited to `CPUQuota=20%`.
