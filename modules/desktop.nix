{ pkgs, ... }: {
  # --- X11 / i3 -------------------------------------------------------------
  # Kept so i3 stays a selectable session at the login screen and remains a
  # working fallback if the Hyprland session misbehaves.
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

  # Compositor for the X11/i3 session only; Hyprland composites itself.
  services.picom.enable = true;

  # --- Wayland / Hyprland ---------------------------------------------------
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    # UWSM is left off: home-manager's hyprland module already wires up
    # hyprland-session.target -> graphical-session.target, which is what
    # starts the Waybar user service.
    withUWSM = false;
  };

  services.displayManager.defaultSession = "hyprland";

  environment.sessionVariables.TERMINAL = "alacritty";

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  environment.systemPackages = with pkgs; [
    firefox
    libnotify

    # X11/i3 session tools (wallpaper + screenshots)
    feh
    maim
    xclip

    # Wayland/Hyprland session tools (screenshots + clipboard)
    grim
    slurp
    wl-clipboard
  ];
}
