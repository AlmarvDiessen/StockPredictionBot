{ pkgs, ... }:
let
  # nixos-26.05's claude-code is pinned to 2.1.223 (built 2026-08-05); claude-env's
  # marketplace pins need 2.1.324+. Override to the current stable release until the
  # channel catches up.
  claude-code = pkgs.claude-code.override {
    manifest = {
      version = "2.1.326";
      platforms.linux-x64 = {
        binary = "claude";
        checksum = "b6b3647d981130dc44fc670846ae97b6cde531ffb667cf9c4d17cfcafb38cb37";
        size = 371429904;
      };
    };
  };
in {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  services.upower.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # --- USB HID Devices (wireless keyboards/mice) ---
  services.udev.enable = true;

  boot.kernelModules = [ "hid" "hid_generic" "usbhid" ];
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  time.timeZone = "Europe/Amsterdam";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nl_NL.UTF-8";
    LC_IDENTIFICATION = "nl_NL.UTF-8";
    LC_MEASUREMENT = "nl_NL.UTF-8";
    LC_MONETARY = "nl_NL.UTF-8";
    LC_NAME = "nl_NL.UTF-8";
    LC_NUMERIC = "nl_NL.UTF-8";
    LC_PAPER = "nl_NL.UTF-8";
    LC_TELEPHONE = "nl_NL.UTF-8";
    LC_TIME = "nl_NL.UTF-8";
  };

  users.users.almar = {
    isNormalUser = true;
    uid = 1000;
    description = "almar";
    extraGroups = [ "networkmanager" "wheel" "input" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFNw6BbKPArqCBx03vXL06S0nqWcdUGLMgrq9sUKvqGq almar-head"
    ];
  };

  services.openssh.enable = true;
  services.tailscale.enable = true;

  programs.nix-ld.enable = true;

  environment.systemPackages = [ claude-code pkgs.git pkgs.nodejs_22 pkgs.gh ];
}
