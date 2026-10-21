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

  polybarSettings = {
    "bar/main" = {
      width = "100%";
      height = 26;
      background = bg;
      foreground = text;
      padding-left = 1;
      padding-right = 1;
      font-0 = "${font}:size=10;2";
      modules-left = "gpu";
      modules-center = "date";
      modules-right = "weather";
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
  ] ++ (with pkgs; [ nil nixfmt ]);

  xdg.configFile."polybar/config.ini".source =
    (pkgs.formats.ini { }).generate "polybar-config.ini" polybarSettings;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraLuaConfig = ''
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
    extraConfig = "exec_always --no-startup-id ${barLaunch}";
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
