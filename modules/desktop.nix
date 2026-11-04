{ config, pkgs, ... }: {
  # --- Wayland / Hyprland ---------------------------------------------------
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  services.displayManager.defaultSession = "hyprland";

  # swaylock (bound to $mod,L; see home/default.nix lockCmd) ships no PAM
  # service file by default, so without this it cannot authenticate at all
  # -- the lock screen would be unlockable with any password.
  security.pam.services.swaylock = {};

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

  environment.sessionVariables.TERMINAL = "kitty";

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  environment.systemPackages = with pkgs; [
    firefox
    libnotify

    # Wayland/Hyprland session tools (screenshots + clipboard)
    grim
    slurp
    wl-clipboard
  ];
}
