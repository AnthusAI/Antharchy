#!/bin/bash
set -euo pipefail
export OMARCHY_PATH=/antharchy-repo/build/src
export PATH="$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export LIBSEAT_BACKEND=seatd
export AQ_NO_MODIFIERS=1
export AQ_DRM_DEVICES=/dev/dri/card0
export GALLIUM_DRIVER=llvmpipe
# Headless mode was investigated and does NOT work with this build (Hyprland
# v0.56.1 / aquamarine 0.15.0): unsetting/invalidating AQ_DRM_DEVICES makes
# CBackend::create() throw immediately ("CBackend::create() failed!") and
# Hyprland crashes on startup. There is no working headless fallback in this
# build, so we stay on the real DRM/virtio-gpu backend.
#
# These are attempted mitigations for the "Cannot commit when a page-flip is
# awaiting" deadlock that occurs once a screencopy client (wayvnc, grim)
# requests a continuous/second frame capture. None of them fixed it in
# testing (see lima/run-hyprland.sh history / session notes) but they are
# harmless and left enabled in case they help on a future aquamarine/qemu
# version:
export AQ_NO_ATOMIC=1
export AQ_FORCE_LINEAR_BLIT=1
export AQ_MGPU_NO_EXPLICIT=1
mkdir -p "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/wayland-*.lock
dbus-run-session /usr/bin/Hyprland &
HYPR_PID=$!

# Wait for the Wayland socket to appear, then start wayvnc serving the
# compositor's output over the wayland-1 socket. Even with the mitigations
# above, wayvnc's continuous screencopy capture currently deadlocks against
# aquamarine's DRM commit cycle under QEMU's software virtio-gpu (confirmed
# via `grim` and a real VNC client both hanging indefinitely once attached).
for i in $(seq 1 30); do
    [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break
    sleep 0.5
done
WAYLAND_DISPLAY=wayland-1 wayvnc -o Virtual-1 0.0.0.0 5900 &

wait "$HYPR_PID"
