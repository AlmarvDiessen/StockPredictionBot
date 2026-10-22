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

  # "#RRGGBB" -> a truecolour SGR foreground code, so terminal output can be
  # coloured straight from the palette above.
  sgrOf = c:
    let
      h = hexOf c;
      comp = i: toString (lib.fromHexString (builtins.substring i 2 h));
    in "38;2;${comp 0};${comp 2};${comp 4}";

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

  gpuStatus = pkgs.writeShellScript "gpu-status" ''
    read -r temp util <<< "$(/run/current-system/sw/bin/nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits | tr -d ',')"
    echo "GPU ''${temp}°C ''${util}%"
  '';

  weatherStatus = pkgs.writeShellScript "weather-status" ''
    ${pkgs.curl}/bin/curl -s "https://wttr.in/Delfzijl?format=%t" || echo "--"
  '';

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

  # fastfetch's battery module exposes capacity and cycle count but not
  # energy_full / energy_full_design, so battery health needs its own script.
  # Installed into the profile because the fastfetch config calls it by name.
  batteryHealth = pkgs.writeShellScriptBin "battery-health" ''
    bat=/sys/class/power_supply/BAT0
    # Most laptops expose energy_* (uWh); some expose charge_* (uAh) instead.
    if [ -r "$bat/energy_full" ] && [ -r "$bat/energy_full_design" ]; then
      full=$(cat "$bat/energy_full"); design=$(cat "$bat/energy_full_design"); unit=Wh
    elif [ -r "$bat/charge_full" ] && [ -r "$bat/charge_full_design" ]; then
      full=$(cat "$bat/charge_full"); design=$(cat "$bat/charge_full_design"); unit=Ah
    else
      echo "unavailable"; exit 0
    fi
    [ "$design" -gt 0 ] 2>/dev/null || { echo "unavailable"; exit 0; }
    tenths=$(( full * 1000 / design ))
    printf '%d.%d%%  (%d.%02d %s of %d.%02d %s)\n' \
      $(( tenths / 10 )) $(( tenths % 10 )) \
      $(( full / 1000000 )) $(( (full % 1000000) / 10000 )) "$unit" \
      $(( design / 1000000 )) $(( (design % 1000000) / 10000 )) "$unit"
  '';

  # Super+i: fastfetch in a floating terminal. The --class is what the
  # Hyprland window rules below match on (it becomes the Wayland app_id).
  sysInfo = pkgs.writeShellScript "sysinfo" ''
    export PATH=${batteryHealth}/bin:$PATH
    exec ${pkgs.alacritty}/bin/alacritty --class sysinfo \
      -e ${pkgs.bash}/bin/bash -c \
      '${pkgs.fastfetch}/bin/fastfetch; printf "\n  press q to close  "; while :; do IFS= read -rsn1 k || exit 0; [ "$k" = q ] && exit 0; done'
  '';

  # Super+/: the shortcut cheatsheet. Rendered from `hyprctl binds -j`, so
  # it lists whatever is actually bound right now rather than a hand-kept
  # copy that drifts. Only binds declared with `bindd` show up.
  shortcutsHelp = pkgs.writeShellScript "hypr-shortcuts" ''
    exec ${pkgs.alacritty}/bin/alacritty --class hyprhelp -o font.size=9 \
      -e ${pkgs.bash}/bin/bash -c \
      '${pkgs.hyprland}/bin/hyprctl binds -j \
         | ${pkgs.jq}/bin/jq -r \
             --arg accent  "${sgrOf accent}" \
             --arg text    "${sgrOf text}" \
             --arg muted   "${sgrOf muted}" \
             --arg surface "${sgrOf surface}" \
             -f ${../assets/hypr/shortcuts.jq} \
         | ${pkgs.less}/bin/less -R'
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

  home.packages = [ batteryHealth ]
    ++ (with pkgs; [ nil nixfmt jq ]);

  # X11 supplied a cursor implicitly; Wayland does not. Without a theme the
  # compositor still draws its built-in fallback, but XWayland and GTK apps
  # fall back separately and end up inconsistent. Setting it once exports
  # XCURSOR_THEME/XCURSOR_SIZE and writes the GTK and hyprcursor settings.
  # adwaita-icon-theme is already in the closure via ReGreet.
  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };

  programs.fastfetch.enable = true;

  # programs.fastfetch only writes this file when `settings` is non-empty,
  # so the repo copy (which keeps its comments) can own it outright.
  xdg.configFile."fastfetch/config.jsonc".source = ../assets/fastfetch/config.jsonc;

  programs.neovim = {
    enable = true;
    defaultEditor = true;

    plugins = with pkgs.vimPlugins; [
      nvim-web-devicons
      nvim-tree-lua
      plenary-nvim
      telescope-nvim
      telescope-fzf-native-nvim
    ];

    # Telescope shells out to these for find_files and live_grep.
    extraPackages = with pkgs; [ ripgrep fd ];

    initLua = ''
      -- Leader has to be set before any plugin reads a mapping.
      vim.g.mapleader = ' '
      vim.g.maplocalleader = ' '

      -- nvim-tree replaces netrw, which must be disabled before it loads.
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1

      vim.o.termguicolors = true
      vim.o.number = true
      vim.o.signcolumn = 'yes'
      vim.o.splitright = true
      vim.o.splitbelow = true

      -- ---- palette -------------------------------------------------------
      local bg      = '${bg}'
      local surface = '${surface}'
      local text    = '${text}'
      local accent  = '${accent}'
      local muted   = '${muted}'

      local function theme()
        local hl = vim.api.nvim_set_hl
        hl(0, 'Normal',       { fg = text, bg = bg })
        hl(0, 'NormalFloat',  { fg = text, bg = bg })
        hl(0, 'FloatBorder',  { fg = accent, bg = bg })
        hl(0, 'Comment',      { fg = muted, italic = true })
        hl(0, 'LineNr',       { fg = muted })
        hl(0, 'CursorLineNr', { fg = accent, bold = true })
        hl(0, 'CursorLine',   { bg = surface })
        hl(0, 'Visual',       { bg = surface })
        hl(0, 'Search',       { fg = bg, bg = accent })
        hl(0, 'IncSearch',    { fg = bg, bg = accent })
        hl(0, 'StatusLine',   { fg = text, bg = surface })
        hl(0, 'WinSeparator', { fg = surface, bg = bg })
        hl(0, 'Pmenu',        { fg = text, bg = surface })
        hl(0, 'PmenuSel',     { fg = bg, bg = accent })
        hl(0, 'Directory',    { fg = accent })
        hl(0, 'Title',        { fg = accent, bold = true })
        hl(0, 'ErrorMsg',     { fg = accent })

        -- file tree
        hl(0, 'NvimTreeNormal',           { fg = text, bg = bg })
        hl(0, 'NvimTreeWinSeparator',     { fg = surface, bg = bg })
        hl(0, 'NvimTreeRootFolder',       { fg = accent, bold = true })
        hl(0, 'NvimTreeFolderName',       { fg = text })
        hl(0, 'NvimTreeOpenedFolderName', { fg = accent, bold = true })
        hl(0, 'NvimTreeFolderIcon',       { fg = accent })
        hl(0, 'NvimTreeIndentMarker',     { fg = surface })
        hl(0, 'NvimTreeCursorLine',       { bg = surface })

        -- telescope
        hl(0, 'TelescopeNormal',       { fg = text, bg = bg })
        hl(0, 'TelescopeBorder',       { fg = accent, bg = bg })
        hl(0, 'TelescopePromptBorder', { fg = accent, bg = bg })
        hl(0, 'TelescopePromptTitle',  { fg = bg, bg = accent })
        hl(0, 'TelescopeResultsTitle', { fg = bg, bg = accent })
        hl(0, 'TelescopePreviewTitle', { fg = bg, bg = accent })
        hl(0, 'TelescopeSelection',    { fg = text, bg = surface })
        hl(0, 'TelescopeMatching',     { fg = accent, bold = true })
      end

      theme()
      vim.api.nvim_create_autocmd('ColorScheme', { callback = theme })

      -- ---- file tree -----------------------------------------------------
      require('nvim-tree').setup({
        view = { side = 'left', width = 32 },
        renderer = {
          group_empty = true,
          indent_markers = { enable = true },
        },
        filters = { dotfiles = false },
      })

      -- ---- fuzzy finder --------------------------------------------------
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          -- ASCII only: literal Nerd Font glyphs are easy to mangle, and
          -- the icons that matter come from nvim-web-devicons anyway.
          prompt_prefix = '> ',
          selection_caret = '> ',
          sorting_strategy = 'ascending',
          layout_config = { prompt_position = 'top' },
        },
      })
      pcall(telescope.load_extension, 'fzf')

      -- ---- keymaps -------------------------------------------------------
      local map = vim.keymap.set
      map('n', '<leader>e', '<cmd>NvimTreeToggle<cr>',  { desc = 'Toggle file tree' })
      map('n', '<leader>f', '<cmd>Telescope find_files<cr>', { desc = 'Find files' })
      map('n', '<leader>g', '<cmd>Telescope live_grep<cr>',  { desc = 'Grep files' })
      map('n', '<leader>b', '<cmd>Telescope buffers<cr>',    { desc = 'Buffers' })

      map('n', '<C-h>', '<C-w>h', { desc = 'Window left' })
      map('n', '<C-j>', '<C-w>j', { desc = 'Window down' })
      map('n', '<C-k>', '<C-w>k', { desc = 'Window up' })
      map('n', '<C-l>', '<C-w>l', { desc = 'Window right' })

      -- ---- LSP -----------------------------------------------------------
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
        # The original 1.0/0.92 pair was effectively invisible: the focused
        # window was fully opaque and 8% on the rest reads as nothing. These
        # values were picked by setting them live and comparing screenshots.
        active_opacity = 0.90;
        inactive_opacity = 0.78;
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

      # Every bind is declared with `bindd`, which attaches a description
      # that Hyprland reports back through `hyprctl binds -j`. The Super+/
      # cheatsheet is rendered from that, so the help can never drift out of
      # sync with the real keymap.
      #
      # Descriptions must not contain commas: bindd splits its fields on
      # commas with a bounded count, and the description is a middle field,
      # so only the trailing dispatcher args may contain them.
      bindd = [
        # --- the bindings carried over from i3 ---
        "$mod, D, Open the rofi application launcher to search and start any installed program, exec, ${pkgs.rofi}/bin/rofi -show drun"
        "$mod, T, Open a new Alacritty terminal window on the current active workspace, exec, ${pkgs.alacritty}/bin/alacritty"
        "ALT, Tab, Switch to another open window by picking it from the rofi list, exec, ${pkgs.rofi}/bin/rofi -show window"
        "$mod, F, Toggle real fullscreen on the focused window hiding its border and bar, fullscreen, 0"
        "$mod SHIFT, Q, Close the currently focused window and free the screen space it used, killactive"
        "$mod SHIFT, R, Reload the Hyprland configuration from disk without restarting your running desktop session, exec, ${pkgs.hyprland}/bin/hyprctl reload"
        "$mod SHIFT, E, Open the exit menu to lock log out reboot or shut down, exec, ${exitMenu}"
        "$mod, L, Lock the screen straight away using swaylock showing the desktop wallpaper, exec, ${lockCmd}"
        "$mod SHIFT, S, Select a screen region and save that screenshot into your Pictures folder, exec, ${screenshotFile}"
        "$mod SHIFT, C, Select a screen region and copy that screenshot directly to the clipboard, exec, ${screenshotClip}"
        "$mod, G, Arrange exactly four windows on the active workspace into a tidy grid, exec, ${hyprGrid}"
        "$mod, I, Show system information including model memory graphics driver and battery health, exec, ${sysInfo}"
        "$mod, slash, Open this shortcut helper listing every key binding with a written description, exec, ${shortcutsHelp}"

        # i3 default: Mod+Return opens a terminal
        "$mod, Return, Open a new Alacritty terminal window matching the old i3 keyboard binding, exec, ${pkgs.alacritty}/bin/alacritty"

        # i3 default: focus / move with the arrow keys. All four share one
        # description so the cheatsheet collapses them onto a single row.
        "$mod, left, Move the keyboard focus to the neighbouring window in that direction, movefocus, l"
        "$mod, down, Move the keyboard focus to the neighbouring window in that direction, movefocus, d"
        "$mod, up, Move the keyboard focus to the neighbouring window in that direction, movefocus, u"
        "$mod, right, Move the keyboard focus to the neighbouring window in that direction, movefocus, r"
        "$mod SHIFT, left, Move the focused window one place in that direction inside the layout, movewindow, l"
        "$mod SHIFT, down, Move the focused window one place in that direction inside the layout, movewindow, d"
        "$mod SHIFT, up, Move the focused window one place in that direction inside the layout, movewindow, u"
        "$mod SHIFT, right, Move the focused window one place in that direction inside the layout, movewindow, r"

        # i3 default: split orientation (dwindle folds both onto togglesplit)
        "$mod, H, Toggle whether the next window opens beside or below the focused one, layoutmsg, togglesplit"
        "$mod, V, Toggle whether the next window opens beside or below the focused one, layoutmsg, togglesplit"

        # i3 default: stacking / tabbed layouts -> pseudo / groups
        "$mod, S, Toggle pseudo tiling so the focused window keeps its own preferred size, pseudo"
        "$mod, W, Group the focused window together with its neighbours into one tabbed container, togglegroup"
        "$mod, E, Cycle forward through the windows held inside the currently focused tabbed group, changegroupactive, f"

        # i3 default: floating toggle and window cycling
        "$mod SHIFT, space, Toggle the focused window between floating freely and being tiled normally, togglefloating"
        "$mod, space, Move the keyboard focus onwards to the next window on this workspace, cyclenext"

        # i3 default: scratchpad -> special workspace
        "$mod SHIFT, minus, Send the focused window into the hidden scratchpad workspace without following it, movetoworkspacesilent, special:scratchpad"
        "$mod, minus, Show or hide the scratchpad workspace where you stash windows away, togglespecialworkspace, scratchpad"

        # i3 default: resize mode
        "$mod, R, Enter resize mode where the arrow keys resize the currently focused window, submap, resize"
      ]
      ++ (builtins.concatMap
        (n:
          let ws = if n == 0 then "10" else toString n;
          in [
            "$mod, ${toString n}, Switch the current monitor to that workspace and show the windows on it, workspace, ${ws}"
            "$mod SHIFT, ${toString n}, Send the focused window to that workspace without moving your view there, movetoworkspace, ${ws}"
          ])
        [ 1 2 3 4 5 6 7 8 9 0 ]);

      binddm = [
        "$mod, mouse:272, Hold Super and drag with the left mouse button to move windows, movewindow"
        "$mod, mouse:273, Hold Super and drag with the right mouse button to resize windows, resizewindow"
      ];

      # Hyprland 0.53 replaced the old "<rule>, <selector>" window rule
      # grammar with comma-separated "<field> <value>" pairs: match
      # properties are spelled "match:<prop> <regex>", and every effect now
      # needs an explicit value (bare "float"/"center" are a parse error).
      # One rule line can carry several effects, so the three old lines
      # collapse into one. Verified against 0.55.4 with Hyprland
      # --verify-config.
      windowrule = [
        "match:class ^(sysinfo)$, float true, size 900 600, center true"
        # Taller than the info screen: the cheatsheet is a long list. The
        # panel is 1280x720 logical (1920x1080 at scale 1.5) so this leaves
        # a margin on every side.
        "match:class ^(hyprhelp)$, float true, size 1200 684, center true"
      ];
    };

    submaps.resize = {
      settings = {
        bindde = [
          ", right, Grow or shrink the focused window by twenty pixels in that direction, resizeactive, 20 0"
          ", left, Grow or shrink the focused window by twenty pixels in that direction, resizeactive, -20 0"
          ", up, Grow or shrink the focused window by twenty pixels in that direction, resizeactive, 0 -20"
          ", down, Grow or shrink the focused window by twenty pixels in that direction, resizeactive, 0 20"
        ];
        bindd = [
          ", escape, Leave resize mode and go back to the normal keyboard binding set, submap, reset"
          ", Return, Leave resize mode and go back to the normal keyboard binding set, submap, reset"
        ];
      };
    };
  };

  services.hyprpaper = {
    enable = true;
    # hyprpaper 0.8 replaced the old one-liner format. `wallpaper` is now a
    # hyprlang special category (a block keyed on monitor) and `preload` is
    # gone entirely -- the only remaining handler is `source`. The old
    # "preload = <path>" / "wallpaper = ,<path>" pair parses without error
    # but registers nothing, and the only hint is a debug line reading
    # "Monitor eDP-1 has no target: no wp will be created".
    #
    # "*" is the all-monitors wildcard, so this survives plugging in an
    # external display. fit_mode = cover is fill: scale to cover, crop the
    # overflow.
    settings = {
      ipc = "on";
      splash = false;
      wallpaper = {
        monitor = "*";
        path = "${wallpaper}";
        fit_mode = "cover";
      };
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
