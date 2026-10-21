{ config, pkgs, ... }: {
  # --- X11 / i3 -------------------------------------------------------------
  # Kept so i3 stays a selectable session at the login screen and remains a
  # working fallback if the Hyprland session misbehaves.
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.xserver.windowManager.i3.enable = true;

  # greetd does not start an X server, so X11 sessions have to bring their
  # own. This installs xinit (startx) and the system xserverrc that starts
  # X with the configured server args; ReGreet prefixes xsession entries
  # with commands.x11_prefix below.
  services.xserver.displayManager.startx.enable = true;

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

  # --- Login screen: greetd + ReGreet --------------------------------------
  # programs.regreet enables services.greetd itself and points its
  # default_session at ReGreet running under the cage compositor.
  programs.regreet = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
      size = 12;
    };

    extraCss = ../assets/regreet/regreet.css;

    settings = {
      background = {
        path = "${../assets/wallpaper.jpg}";
        # GTK ContentFit. "Cover" scales to fill the screen and crops the
        # overflow, which is the fill behaviour used elsewhere; GTK's "Fill"
        # would stretch and distort instead.
        fit = "Cover";
      };

      GTK.application_prefer_dark_theme = true;

      commands = {
        reboot = [ "${pkgs.systemd}/bin/systemctl" "reboot" ];
        poweroff = [ "${pkgs.systemd}/bin/systemctl" "poweroff" ];
        # Applied to entries found in xsessions/ (i3). Absolute path so this
        # does not depend on the greeter's PATH.
        x11_prefix = [ "${pkgs.xinit}/bin/startx" "/usr/bin/env" ];
      };

      appearance.greeting_msg = "head";

      widget.clock = {
        format = "%a %d %b  %H:%M";
        resolution = "1s";
        label_width = 260;
      };
    };
  };

  # ReGreet discovers sessions by expanding each XDG_DATA_DIRS entry into
  # <dir>/xsessions and <dir>/wayland-sessions. systemd system services get
  # no XDG_DATA_DIRS on NixOS, so without this the session list comes up
  # empty and only the compiled-in /usr/share fallback is searched.
  systemd.services.greetd.environment.XDG_DATA_DIRS =
    "${config.services.displayManager.sessionData.desktops}/share:/run/current-system/sw/share";

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
