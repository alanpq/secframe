{
  description = "Secureframe compliance agent via nixpkgs fleet-orbit + osquery";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosModules.default = import ./module.nix;
    nixosModules.secureframe-agent = self.nixosModules.default;

    packages.${system} = {
      inherit (pkgs) fleet-orbit osquery fleet-desktop;
    };

    checks.${system}.module-eval = let
      sys = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "nodev";
              fsType = "ext4";
            };
            system.stateVersion = "24.05";
            nixpkgs.config.allowUnfree = true;
            services.secureframe-agent = {
              enable = true;
              enrollSecretFile = "/run/secrets/secureframe-enroll";
            };
          }
        ];
      };
    in
      pkgs.runCommand "secureframe-agent-module-eval" {} ''
        cat > "$out" <<'EOF'
        ${sys.config.systemd.services.secureframe-agent.serviceConfig.ExecStart}
        EOF
      '';
  };
}
