{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.secureframe-agent;

  # osquery flags passed through after the `--` separator, mirroring the vendor
  # deb's unit (`--host_identifier specified --specified_identifier <id>`).
  hostIdArgs = lib.optionals (cfg.hostIdentifier != null) [
    "--host_identifier"
    "specified"
    "--specified_identifier"
    cfg.hostIdentifier
  ];
  osqueryArgs = hostIdArgs ++ cfg.osquery.extraArgs;
  passthrough = lib.optionals (osqueryArgs != []) (["--"] ++ osqueryArgs);

  execStart = lib.concatStringsSep " " (
    [(lib.getExe cfg.orbit.package)]
    ++ cfg.orbit.extraArgs
    ++ passthrough
  );
in {
  options.services.secureframe-agent = {
    enable = lib.mkEnableOption "the Secureframe compliance agent (Fleet orbit + osquery)";

    orbit = {
      package = lib.mkPackageOption pkgs "fleet-orbit" {};

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra flags passed to orbit before the osquery `--` separator.";
      };
    };
    osquery = {
      package = lib.mkPackageOption pkgs "osquery" {};

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra osquery flags";
      };
    };
    desktop = {
      package = lib.mkPackageOption pkgs "fleet-desktop" {};
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to launch Fleet Desktop (systray). Requires a graphical session and extra
          GTK/WebKit libraries; leave disabled for headless servers.
        '';
      };
    };

    fleetUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://agent.secureframe.com:443";
      description = "URL of the Secureframe (Fleet) server to enroll against.";
    };

    enrollSecretFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/secureframe-enroll";
      description = ''
        Path to a file containing the enroll secret. Loaded at runtime via
        systemd {option}`LoadCredential`.
      '';
    };

    hostIdentifier = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Secureframe host identifier, passed to osquery as
        `--host_identifier specified --specified_identifier <value>`. 
        Falls back to orbit's default uuid-based identification when `null`.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/orbit";
      description = "Writable root directory for orbit/osquery runtime state.";
    };
    logDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/orbit/";
      description = "Writable log directory for orbit/osquery.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable orbit debug logging.";
    };

    insecure = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable TLS certificate verification (testing only).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.secureframe-agent = {
      description = "Secureframe compliance agent (Fleet orbit + osquery)";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      environment = lib.filterAttrs (_: v: v != null) {
        ORBIT_FLEET_URL = cfg.fleetUrl;
        ORBIT_ENROLL_SECRET_PATH = "%d/enroll-secret";

        # Never fetch un-patched binaries from the TUF update server; osqueryd is
        # supplied from the Nix store via the orbit NixOS integration hook.
        ORBIT_DISABLE_UPDATES = "true";
        ORBIT_DISABLE_KEYSTORE = "true";

        ORBIT_ROOT_DIR = toString cfg.dataDir;
        ORBIT_OSQUERY_DB = "${toString cfg.dataDir}/osquery.db";
        ORBIT_LOG_FILE = "${cfg.logDir}/orbit/orbit.log";
        ORBIT_DEBUG = lib.boolToString cfg.debug;
        ORBIT_INSECURE = lib.boolToString cfg.insecure;

        ORBIT_FLEET_DESKTOP = lib.boolToString cfg.desktop.enable;
        NIX_ORBIT_OSQUERYD_PATH = lib.getExe' cfg.osquery.package "osqueryd";
        NIX_ORBIT_OSQUERY_LOG_PATH = "${cfg.logDir}/osquery/";
        NIX_ORBIT_DESKTOP_PATH =
          if cfg.desktop.enable
          then lib.getExe cfg.desktop.package
          else null;
      };

      serviceConfig = {
        ExecStart = execStart;
        LoadCredential = "enroll-secret:${toString cfg.enrollSecretFile}";
        StateDirectory = "orbit";
        LogsDirectory = "orbit";
        WorkingDirectory = cfg.dataDir;
        TimeoutStartSec = 0;
        Restart = "always";
        RestartSec = 10;
        KillMode = "control-group";
        KillSignal = "SIGTERM";
        CPUQuota = "20%";
        # osquery needs root to read system/kernel tables.
        User = "root";
      };
    };
  };
}
