#!/bin/bash
# Seed a Lima guest so it looks like a real Antharchy session: Tokyo Night,
# the About bot avatar, and Option-as-Super (macOS steals Command from VNC).
set -euo pipefail

export OMARCHY_PATH=/antharchy-repo/build/src
export PATH="$OMARCHY_PATH/bin:$PATH"
export HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"

sudo pacman -S --noconfirm --needed fastfetch gum ttf-nerd-fonts-symbols ttf-jetbrains-mono qt6-imageformats perl gtk3

sudo mkdir -p /usr/share/fonts/omarchy /etc/fastfetch /usr/local/bin
sudo cp -a "$OMARCHY_PATH/etc/fastfetch/." /etc/fastfetch/
sudo cp "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" /usr/share/fonts/omarchy/
sudo ln -sfn /usr/share/fontconfig/conf.avail/10-nerd-font-symbols.conf /etc/fonts/conf.d/10-nerd-font-symbols.conf || true
sudo fc-cache -f >/dev/null
sudo install -m 0755 "/antharchy-repo/lima/xdg-terminal-exec" /usr/bin/xdg-terminal-exec
sudo ln -sfn "$OMARCHY_PATH" /usr/share/omarchy
printf 'OMARCHY_PATH=%s\n' "$OMARCHY_PATH" | sudo tee /etc/omarchy.conf >/dev/null

# Everyday terminal should tile, matching the packaged EC2 session.
mkdir -p "$HOME/.config/hypr"
cat >"$HOME/.config/hypr/looknfeel.lua" <<'LUA'
o.window({ class = "foot" }, { float = false })
o.window({ class = "org.codeberg.dnkl.foot" }, { float = false })
LUA

cp -f "$OMARCHY_PATH/default/bashrc" "$HOME/.bashrc"
if ! grep -q '^fastfetch$' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'BASH'

# Packaged Antharchy sessions show the bot in every new terminal.
[[ $- == *i* ]] && command -v fastfetch >/dev/null && fastfetch
BASH
fi
sudo mkdir -p /usr/share/xdg-terminal-exec
sudo cp "$OMARCHY_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" /usr/share/xdg-terminal-exec/

# QEMU's preferred mode is 1280x800; pin 1080p to match a typical EC2 session.
cat >"$HOME/.config/hypr/monitors.lua" <<'LUA'
hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA

mkdir -p "$HOME/.config/omarchy/backgrounds/tokyo-night"
if [[ ! -f $HOME/.config/omarchy/backgrounds/tokyo-night/1-tokyo-night.jpg ]]; then
  curl -fsSL -o "$HOME/.config/omarchy/backgrounds/tokyo-night/1-tokyo-night.jpg" \
    "https://images.unsplash.com/photo-1620207418302-439b387441b0?w=1920" || true
fi

mkdir -p "$HOME/.config/omarchy/branding" "$HOME/.config/foot" "$HOME/.config/hypr"
cp -f "$OMARCHY_PATH/icon.txt" "$HOME/.config/omarchy/branding/about.txt"
cp -f "$OMARCHY_PATH/logo.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
cp -f "$OMARCHY_PATH/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"

# macOS keeps Command for itself. Swap Left Alt and Left Super so Option is Super.
cat >"$HOME/.config/hypr/input.lua" <<'LUA'
hl.config({
  input = {
    kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_lalt_lwin",
  },
})
LUA

# After the swap, Command (if it arrives) is Alt. Keep the menu reachable either way.
cat >"$HOME/.config/hypr/bindings.lua" <<'LUA'
o.bind("ALT + SPACE", "Omarchy menu", "omarchy-menu toggle")
o.bind("ALT + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("ALT + K", "Keybindings", "omarchy-menu-keybindings")
LUA

if [[ ! -s $HOME/.local/state/omarchy/current/theme.name ]]; then
  OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night" || true
fi
