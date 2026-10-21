{ pkgs, ... }: {
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.xserver.windowManager.i3.enable = true;

  services.xserver.displayManager.lightdm = {
    enable = true;
    greeters.gtk = {
      enable = true;
      theme.name = "Adwaita-dark";
      iconTheme.name = "Adwaita";
      extraConfig = ''
        background = /etc/nixos/assets/wallpaper.jpg
        logo =
        clock-format = %H:%M
        indicators = ~host;~clock;~session
      '';
    };
  };

  services.displayManager.defaultSession = "none+i3";

  services.picom.enable = true;

  environment.sessionVariables.TERMINAL = "alacritty";

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  environment.systemPackages = with pkgs; [
    firefox
    feh
    libnotify
    maim
    xclip
  ];
}
