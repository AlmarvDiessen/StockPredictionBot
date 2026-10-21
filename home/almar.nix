{ pkgs, lib, ... }:
let
  bg = "#1b1b1b";
  surface = "#323232";
  text = "#FFE7D0";
  accent = "#FC6E20";
  muted = "#8a8a8a";
  font = "JetBrainsMono Nerd Font";

  # Hyprland wants colours as rgb(RRGGBB) / rgba(RRGGBBAA), swaylock as bare hex.
  hexOf = c: lib.removePrefix "#" c;
  hyprRgb = c: "rgb(${hexOf c})";

  # Nerd Font glyphs, written as codepoints instead of literal characters.
  # Literal private-use characters are easy to lose in transit, and a lost
  # one degrades silently into an empty icon rather than an error, so this
  # file stays pure ASCII. Handles both the BMP and the supplementary plane
  # (where most Material Design icons live) via JSON \u escapes.
  nerd = hex:
    let
      cp = lib.fromHexString hex;
      digits = "0123456789abcdef";
      hex4 = n:
        lib.concatMapStrings (p: builtins.substring (lib.mod (n / p) 16) 1 digits)
          [ 4096 256 16 1 ];
      esc =
        if cp < 65536 then
          "\\u${hex4 cp}"
        else
          let c = cp - 65536;
          in "\\u${hex4 (55296 + (c / 1024))}\\u${hex4 (56320 + (lib.mod c 1024))}";
    in builtins.fromJSON "\"${esc}\"";

  icons = {
    cpu = nerd "f4bc"; # nf-oct-cpu
    calendar = nerd "f073"; # nf-fa-calendar
    thermometer = nerd "f2c9"; # nf-fa-thermometer-half
    batteryCharging = nerd "f0084"; # nf-md-battery-charging
    ethernet = nerd "f0200"; # nf-md-ethernet
    wifiOff = nerd "f092d"; # nf-md-wifi-strength-off
    # 0 -> 4 bars
    wifi = map nerd [ "f092f" "f091f" "f0922" "f0925" "f0928" ];
    # empty -> full
    battery = map nerd [ "f244" "f243" "f242" "f241" "f240" ];
  };

  wallpaper = ../assets/wallpaper.jpg;

  unfocusedColors = {
    background = bg;
    border = surface;
    childBorder = surface;
    indicator = surface;
    text = muted;
  };

  gpuStatus = pkgs.writeShellScript "gpu-status" ''
    read -r temp util <<< "$(/run/current-system/sw/bin/nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits | tr -d ',')"
    echo "GPU ''${temp}°C ''${util}%"
  '';

  weatherStatus = pkgs.writeShellScript "weather-status" ''
    ${pkgs.curl}/bin/curl -s "https://wttr.in/Delfzijl?format=%t" || echo "--"
  '';

  barLaunch = pkgs.writeShellScript "launch-bar" ''
    ${pkgs.procps}/bin/pkill -x polybar || true
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.polybar}/bin/polybar main >/dev/null 2>&1
  '';

  gridScript = pkgs.writeShellScript "i3-grid" ''
    ws=$(${pkgs.i3}/bin/i3-msg -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
    ids=$(${pkgs.i3}/bin/i3-msg -t get_tree | ${pkgs.jq}/bin/jq -r --arg ws "$ws" '.. | objects | select(.type? == "workspace" and .name? == $ws) | .. | objects | select(.window? != null) | .id')
    set -- $ids
    [ $# -eq 4 ] || exit 0
    a=$1; b=$2; c=$3; d=$4
    m() { ${pkgs.i3}/bin/i3-msg "$@" >/dev/null; }
    m "[con_id=$a] mark --add ga"
    m "[con_id=$c] mark --add gc"
    m "[con_id=$a] split vertical"
    m "[con_id=$b] move container to mark ga"
    m "[con_id=$c] split vertical"
    m "[con_id=$d] move container to mark gc"
  '';

  gridWatcher = pkgs.writeShellScript "i3-grid-watch" ''
    ${pkgs.i3}/bin/i3-msg -t subscribe -m '["window"]' | while read -r line; do
      case "$line" in
        *'"change":"new"'*) sleep 0.3; ${gridScript} ;;
      esac
    done
  '';

  polybarSettings = {
    "bar/main" = {
      width = "100%";
      height = 26;
      background = bg;
      foreground = text;
      padding-left = 1;
      padding-right = 1;
      font-0 = "${font}:size=10;2";
      module-margin = 3;
      modules-left = "gpu";
      modules-center = "date";
      modules-right = "battery weather";
    };
    "module/gpu" = {
      type = "custom/script";
      exec = "${gpuStatus}";
      interval = 5;
      format-foreground = accent;
    };
    "module/date" = {
      type = "internal/date";
      interval = 60;
      date = "%a %d %b  %H:%M";
      label = "%date%";
    };
    "module/battery" = {
      type = "internal/battery";
      battery = "BAT0";
      adapter = "ADP0";
      full-at = 100;
      format-charging = "CHG <label-charging>";
      format-discharging = "BAT <label-discharging>";
      format-full = "FULL";
      label-charging = "%percentage%%";
      label-discharging = "%percentage%%";
    };
    "module/weather" = {
      type = "custom/script";
      exec = "${weatherStatus}";
      interval = 600;
      format-foreground = accent;
    };
  };

  # --- Wayland helper scripts ----------------------------------------------

  lockCmd = "${pkgs.swaylock}/bin/swaylock -f";

  screenshotFile = pkgs.writeShellScript "screenshot-file" ''
    set -u
    geom=$(${pkgs.slurp}/bin/slurp) || exit 0
    [ -n "$geom" ] || exit 0
    dir="$HOME/Pictures"
    mkdir -p "$dir"
    out="$dir/screenshot-$(${pkgs.coreutils}/bin/date +%F-%H%M%S).png"
    ${pkgs.grim}/bin/grim -g "$geom" "$out"
    ${pkgs.libnotify}/bin/notify-send "Screenshot" "Saved to $out" || true
  '';

  screenshotClip = pkgs.writeShellScript "screenshot-clip" ''
    set -u
    geom=$(${pkgs.slurp}/bin/slurp) || exit 0
    [ -n "$geom" ] || exit 0
    ${pkgs.grim}/bin/grim -g "$geom" - \
      | ${pkgs.wl-clipboard}/bin/wl-copy --type image/png
    ${pkgs.libnotify}/bin/notify-send "Screenshot" "Copied to clipboard" || true
  '';

  # 2x2 grid for exactly four windows on the active workspace.
  #
  # Dwindle is a binary tree and exposes no dispatcher that can reshape an
  # arbitrary four-window tree into a specific 2x2 with a chosen window->cell
  # mapping (layoutmsg only offers togglesplit/swapsplit/movetoroot/preselect).
  # The master layout can *look* like a 2x2 with two masters, but that is a
  # global mode change affecting every workspace and still gives no control
  # over which window lands where. So this floats the four windows and places
  # them at exact pixel geometry, which is deterministic and verifiable.
  hyprGrid = pkgs.writeShellScript "hypr-grid" ''
    set -euo pipefail
    hyprctl=${pkgs.hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    ws=$("$hyprctl" activeworkspace -j | "$jq" -r '.id')
    mons=$("$hyprctl" monitors -j)

    batch=$("$hyprctl" clients -j \
      | "$jq" -r --argjson mons "$mons" --argjson ws "$ws" -f ${../assets/hypr/grid.jq})

    # Empty means the workspace did not hold exactly four windows.
    [ -n "$batch" ] || exit 0

    "$hyprctl" --batch "$batch" >/dev/null
  '';

  # Replacement for i3-nagbar's exit prompt, themed by the rofi config below.
  exitMenu = pkgs.writeShellScript "exit-menu" ''
    set -u
    choice=$(printf '%s\n' "Lock" "Log out" "Reboot" "Shut down" \
      | ${pkgs.rofi}/bin/rofi -dmenu -i -p "Exit" -lines 4) || exit 0
    case "$choice" in
      "Lock")      exec ${lockCmd} ;;
      "Log out")   exec ${pkgs.hyprland}/bin/hyprctl dispatch exit ;;
      "Reboot")    exec ${pkgs.systemd}/bin/systemctl reboot ;;
      "Shut down") exec ${pkgs.systemd}/bin/systemctl poweroff ;;
    esac
  '';
in {
  home.stateVersion = "26.05";

  home.packages = [
    (pkgs.polybar.override { i3Support = true; })
  ] ++ (with pkgs; [ nil nixfmt xsetroot jq ]);

  xdg.configFile."polybar/config.ini".source =
    (pkgs.formats.ini { }).generate "polybar-config.ini" polybarSettings;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    initLua = ''
      vim.lsp.config('nil_ls', {
        cmd = { 'nil' },
        settings = { ['nil'] = { formatting = { command = { 'nixfmt' } } } },
      })
      vim.lsp.enable('nil_ls')
    '';
  };

  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal.family = font;
        size = 11;
      };
      colors = {
        primary = {
          background = bg;
          foreground = text;
        };
        normal = {
          black = surface;
          red = accent;
          green = muted;
          yellow = accent;
          blue = muted;
          magenta = accent;
          cyan = muted;
          white = text;
        };
        bright = {
          black = muted;
          red = accent;
          green = text;
          yellow = accent;
          blue = text;
          magenta = accent;
          cyan = text;
          white = text;
        };
      };
    };
  };

  # --- Waybar (Hyprland bar) ------------------------------------------------
  # Started by home-manager's systemd user service, which is WantedBy
  # graphical-session.target; hyprland-session.target binds to that. No
  # exec-once / exec_always anywhere.

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = builtins.readFile ../assets/waybar/style.css;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 30;
      # Matches the old polybar module-margin; the stylesheet adds padding.
      spacing = 12;

      modules-left = [ "hyprland/workspaces" "custom/gpu" "cpu" ];
      modules-center = [ "clock" ];
      modules-right = [ "network" "battery" "custom/weather" ];

      "hyprland/workspaces" = {
        format = "{id}";
        on-click = "activate";
        sort-by = "id";
      };

      # The existing gpuStatus script, unchanged: prints "GPU 55°C 12%".
      "custom/gpu" = {
        exec = "${gpuStatus}";
        interval = 5;
        format = "{}";
        tooltip = false;
      };

      # nf-oct-cpu. Nerd Fonts ships no Intel-brand glyph, so this is the
      # generic CPU-type icon.
      cpu = {
        interval = 5;
        format = "${icons.cpu}  {usage}%";
        tooltip = false;
      };

      clock = {
        interval = 60;
        # Date format exactly as before; the calendar glyph is decoration.
        format = "${icons.calendar}  {:%a %d %b  %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
      };

      # Signal strength as an icon (nf-md-wifi-strength-*).
      network = {
        interval = 5;
        format-wifi = "{icon}";
        format-ethernet = icons.ethernet;
        format-linked = icons.ethernet;
        format-disconnected = icons.wifiOff;
        format-icons = icons.wifi;
        tooltip-format-wifi = "{essid}  {signalStrength}%\n{ipaddr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}";
        tooltip-format-disconnected = "Disconnected";
      };

      battery = {
        bat = "BAT0";
        adapter = "ADP0";
        full-at = 100;
        interval = 30;
        states = {
          warning = 20;
          critical = 10;
        };
        # format-<status> keys come from /sys/class/power_supply/BAT0/status
        # lowercased: Discharging -> format-discharging, and so on.
        format = "BAT {icon} {capacity}%";
        format-discharging = "BAT {icon} {capacity}%";
        format-charging = "CHG ${icons.batteryCharging} {capacity}%";
        format-plugged = "CHG ${icons.batteryCharging} {capacity}%";
        format-full = "FULL {icon}";
        format-icons = icons.battery;
        tooltip-format = "{timeTo}  ({power}W)";
      };

      # The existing weatherStatus script, unchanged: wttr.in Delfzijl.
      "custom/weather" = {
        exec = "${weatherStatus}";
        interval = 600;
        format = "${icons.thermometer}  {}";
        tooltip = false;
      };
    };
  };

  # --- Hyprland -------------------------------------------------------------

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    # home-manager 26.05 defaults this to "lua" for stateVersion >= 26.05.
    # Pin hyprlang so the config stays the documented hyprland.conf format.
    configType = "hyprlang";

    # Emits the exec-once that starts hyprland-session.target, which is what
    # pulls in graphical-session.target (and therefore the Waybar service).
    systemd.enable = true;

    settings = {
      "$mod" = "SUPER";

      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        "col.active_border" = hyprRgb accent;
        "col.inactive_border" = hyprRgb surface;
        layout = "dwindle";
        resize_on_border = true;
      };

      decoration = {
        rounding = 0;
        active_opacity = 1.0;
        inactive_opacity = 0.92;
        fullscreen_opacity = 1.0;
        blur = {
          enabled = true;
          size = 6;
          passes = 3;
          new_optimizations = true;
          xray = true;
        };
        shadow.enabled = false;
      };

      dwindle = {
        preserve_split = true;
      };

      # WLR_NO_HARDWARE_CURSORS is set system-wide; this is the setting
      # Hyprland 0.55 actually reads for the same effect.
      cursor = {
        no_hardware_cursors = true;
      };

      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        touchpad.natural_scroll = false;
      };

      bind = [
        # --- the bindings carried over from i3 ---
        "$mod, D, exec, ${pkgs.rofi}/bin/rofi -show drun"
        "$mod, T, exec, ${pkgs.alacritty}/bin/alacritty"
        "ALT, Tab, exec, ${pkgs.rofi}/bin/rofi -show window"
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, Q, killactive"
        "$mod SHIFT, R, exec, ${pkgs.hyprland}/bin/hyprctl reload"
        "$mod SHIFT, E, exec, ${exitMenu}"
        "$mod, L, exec, ${lockCmd}"
        "$mod SHIFT, S, exec, ${screenshotFile}"
        "$mod SHIFT, C, exec, ${screenshotClip}"
        "$mod, G, exec, ${hyprGrid}"

        # i3 default: Mod+Return opens a terminal
        "$mod, Return, exec, ${pkgs.alacritty}/bin/alacritty"

        # i3 default: focus / move with the arrow keys
        "$mod, left, movefocus, l"
        "$mod, down, movefocus, d"
        "$mod, up, movefocus, u"
        "$mod, right, movefocus, r"
        "$mod SHIFT, left, movewindow, l"
        "$mod SHIFT, down, movewindow, d"
        "$mod SHIFT, up, movewindow, u"
        "$mod SHIFT, right, movewindow, r"

        # i3 default: split orientation (dwindle folds both onto togglesplit)
        "$mod, H, layoutmsg, togglesplit"
        "$mod, V, layoutmsg, togglesplit"

        # i3 default: stacking / tabbed layouts -> pseudo / groups
        "$mod, S, pseudo"
        "$mod, W, togglegroup"
        "$mod, E, changegroupactive, f"

        # i3 default: floating toggle and window cycling
        "$mod SHIFT, space, togglefloating"
        "$mod, space, cyclenext"

        # i3 default: scratchpad -> special workspace
        "$mod SHIFT, minus, movetoworkspacesilent, special:scratchpad"
        "$mod, minus, togglespecialworkspace, scratchpad"

        # i3 default: resize mode
        "$mod, R, submap, resize"
      ]
      ++ (builtins.concatMap
        (n:
          let ws = if n == 0 then "10" else toString n;
          in [
            "$mod, ${toString n}, workspace, ${ws}"
            "$mod SHIFT, ${toString n}, movetoworkspace, ${ws}"
          ])
        [ 1 2 3 4 5 6 7 8 9 0 ]);

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };

    submaps.resize = {
      settings = {
        binde = [
          ", right, resizeactive, 20 0"
          ", left, resizeactive, -20 0"
          ", up, resizeactive, 0 -20"
          ", down, resizeactive, 0 20"
        ];
        bind = [
          ", escape, submap, reset"
          ", Return, submap, reset"
        ];
      };
    };
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      splash = false;
      preload = [ "${wallpaper}" ];
      # "<monitor>,<path>" with an empty monitor means every output.
      # hyprpaper's default render mode scales to cover, i.e. fill.
      wallpaper = [ ",${wallpaper}" ];
    };
  };

  programs.swaylock = {
    enable = true;
    settings = {
      image = "${wallpaper}";
      scaling = "fill";
      ignore-empty-password = true;
      show-failed-attempts = true;
      indicator-radius = 90;
      indicator-thickness = 8;
      font = font;
      # swaylock takes bare hex, no leading '#'.
      ring-color = hexOf accent;
      ring-ver-color = hexOf accent;
      ring-wrong-color = hexOf accent;
      ring-clear-color = hexOf accent;
      inside-color = hexOf bg;
      inside-ver-color = hexOf bg;
      inside-wrong-color = hexOf bg;
      inside-clear-color = hexOf bg;
      key-hl-color = hexOf text;
      bs-hl-color = hexOf accent;
      separator-color = hexOf surface;
      line-color = hexOf bg;
      line-ver-color = hexOf bg;
      line-wrong-color = hexOf bg;
      line-clear-color = hexOf bg;
      text-color = hexOf text;
      text-ver-color = hexOf text;
      text-wrong-color = hexOf text;
      text-clear-color = hexOf text;
    };
  };

  # --- i3 (fallback session) ------------------------------------------------

  xsession.windowManager.i3 = {
    enable = true;
    extraConfig = ''
      exec_always --no-startup-id feh --no-fehbg --bg-fill ${wallpaper}
      exec --no-startup-id ${barLaunch}
      exec --no-startup-id ${gridWatcher}
    '';
    config = {
      modifier = "Mod4";
      terminal = "alacritty";
      fonts = {
        names = [ font ];
        size = 10.0;
      };
      bars = [ ];
      window.border = 2;
      floating.border = 2;
      gaps = {
        inner = 0;
        outer = 0;
      };
      colors = {
        focused = {
          background = bg;
          border = accent;
          childBorder = accent;
          indicator = accent;
          text = text;
        };
        focusedInactive = unfocusedColors;
        unfocused = unfocusedColors;
        urgent = {
          background = bg;
          border = accent;
          childBorder = accent;
          indicator = accent;
          text = accent;
        };
        placeholder = unfocusedColors;
      };
      keybindings = lib.mkOptionDefault {
        "Mod4+d" = "exec rofi -show drun";
        "Mod4+t" = "exec alacritty";
        "Mod1+Tab" = "exec rofi -show window";
        "Mod4+Shift+s" = "exec maim -s ~/Pictures/screenshot-$(date +%F-%H%M%S).png";
        "Mod4+Shift+c" = "exec maim -s | xclip -selection clipboard -t image/png";
        "Mod4+g" = "exec ${gridScript}";
      };
    };
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "${font} 10";
        frame_width = 2;
        width = 320;
        origin = "top-right";
        offset = "12x12";
      };
      urgency_normal = {
        background = bg;
        foreground = text;
        frame_color = accent;
        timeout = 5;
      };
      urgency_critical = {
        background = bg;
        foreground = accent;
        frame_color = accent;
        timeout = 0;
      };
    };
  };

  programs.rofi = {
    enable = true;
    font = "${font} 12";
    terminal = "alacritty";
    extraConfig = {
      show-icons = true;
      modi = "drun,run,window";
    };
  };
}
