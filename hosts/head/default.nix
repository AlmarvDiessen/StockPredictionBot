{ ... }: {
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "head";
  system.stateVersion = "26.05";
}
