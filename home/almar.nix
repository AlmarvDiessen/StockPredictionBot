		{ pkgs, lib, ... }:
let
  bg = "#1b1b1b";
  surface = "#323232";
  text = "#FFE7D0";
  accent = "#FC6E20";
  muted = "#8a8a8a";
  font = "JetBrainsMono Nerd Font";

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
in {
  home.stateVersion = "26.05";

  home.packages = [
    (pkgs.polybar.override { i3Support = true; })
  ] ++ (with pkgs; [ nil nixfmt xsetroot ]);

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

  xsession.windowManager.i3 = {
    enable = true;
       extraConfig = ''
         exec_always --no-startup-id feh --no-fehbg --bg-fill ~/Pictures/wallpaper.jpg
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
