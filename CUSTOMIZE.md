# Making this machine yours

This is a shared Hyprland NixOS base. If you're reading this, `bootstrap.sh` has
already cloned the config to `/etc/nixos`, regenerated `hardware-configuration.nix`
for your hardware, and run `nixos-rebuild switch` — so you should already be looking
at a working Hyprland desktop.

**One hard prerequisite**: this base enables the proprietary NVIDIA driver
(`modules/nvidia.nix`). It needs an NVIDIA GPU to boot correctly. If your machine
doesn't have one, say so in the prompt below and ask for that module to be removed
instead of configured.

Right now the system uses a generic placeholder: username `user`, no SSH key
authorized, and Dutch defaults (Europe/Amsterdam timezone, `nl_NL` locale, weather
pinned to Delfzijl). None of that is really going to be right for you.

## What to do

Open a terminal, `cd /etc/nixos`, start Claude Code (`claude`), and paste the
following as your first message:

---

> This machine was just bootstrapped from a shared Hyprland NixOS base template.
> I want to personalize it for myself. Please:
>
> 1. Ask me what username I want (the base currently uses the placeholder `user` in
>    `modules/base.nix` and `flake.nix`'s `home-manager.users.user`) and rename it
>    everywhere consistently.
> 2. Ask whether I have an NVIDIA GPU. If not, remove `modules/nvidia.nix` and its
>    import in `flake.nix`, and ask what GPU/video driver I do need instead.
> 3. Ask for my SSH public key to put in `authorizedKeys`, or confirm I'd rather just
>    set a login password with `passwd` and skip SSH entirely.
> 4. Ask whether to keep the Europe/Amsterdam timezone / `nl_NL` locale / Delfzijl
>    weather defaults in `modules/base.nix` and `home/default.nix`, or change them to
>    mine.
> 5. Ask if I want to rename the host (currently `head`, under `hosts/head/`) to
>    something else.
> 6. After these are settled, run `nixos-rebuild switch --flake /etc/nixos#<host>`
>    and confirm it builds, then tell me what changed.
>
> Beyond that, this is meant to be a starting point — feel free to suggest or make
> further Hyprland/theme/keybinding tweaks as I ask for them.

---

That's it — Claude will walk you through the rest.
