#!/bin/bash
set -euo pipefail
export OMARCHY_PATH=/antharchy
export PATH="$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin:/bin"
export HOME=/home/home.guest
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export LIBGL_ALWAYS_SOFTWARE=1
export LIBSEAT_BACKEND=seatd
export AQ_NO_MODIFIERS=1
export AQ_DRM_DEVICES=/dev/dri/card0
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
mkdir -p "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/wayland-*.lock
exec dbus-run-session /usr/bin/Hyprland
