#!/usr/bin/env bash
# Rebuild a machine from this base config.
#
# Use case: a laptop with a minimal NixOS already installed (e.g. freshly
# flashed from a USB stick). Running this pulls in the full Hyprland base
# setup and switches to it.
#
# Prerequisites on the target machine:
#   - git (nix-shell -p git if it's not installed yet)
#   - an SSH key with read access to this repo
#
# Usage (as root):
#   git clone -b nixos-base git@github.com:AlmarvDiessen/StockPredictionBot.git /etc/nixos
#   /etc/nixos/bootstrap.sh
#
# If /etc/nixos already has something in it, move it aside first:
#   mv /etc/nixos /etc/nixos.orig

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root (sudo)." >&2
  exit 1
fi

REPO_DIR="/etc/nixos"
HOST="head"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Expected this script to run from a clone at $REPO_DIR" >&2
  exit 1
fi

echo "==> Regenerating hardware-configuration.nix for this machine"
nixos-generate-config --show-hardware-config > "$REPO_DIR/hosts/$HOST/hardware-configuration.nix"

echo "==> Rebuilding system from the base flake"
nixos-rebuild switch --flake "$REPO_DIR#$HOST"

echo "==> Done. A reboot is recommended."
echo "==> Next: open Claude Code in /etc/nixos and paste the prompt from CUSTOMIZE.md"
echo "    to personalize this machine (username, SSH key, timezone, GPU driver, ...)."
