# vm/ — sources for the `antharchy-vm` package

Salvaged from the retired `antharchy-arm-utm` builder. **Renamed but not yet rewritten** —
these are still the scripts as they ran inside that VM, kept verbatim so nothing is lost in
translation. Packaging them is Phase 6.

Everything here addresses one underlying problem: **virtio-gpu without working acceleration**.
That is why Lima on Apple Silicon and a headless Graviton EC2 instance need the same code, and
why it belongs in a package rather than in either provisioner.

| File | Problem it solves |
|---|---|
| `bin/antharchy-vm-gpu` | GPU clients map but never paint under virtio-gpu/virgl. Forces llvmpipe (`LIBGL_ALWAYS_SOFTWARE`) |
| `bin/antharchy-vm-display` | Omarchy assumes a 2× retina display; QEMU negotiates 1280×800. Pins a sane mode at scale 1 |
| `bin/antharchy-vm-vdagent` | The stock SPICE vdagent is X11-only and dies under Hyprland. Reimplements the udscs protocol against `wl-copy`/`wl-paste` |
| `bin/antharchy-vm-share` | 9p/WebDAV host folder sharing |
| `bin/antharchy-vm-clipboard` | Clipboard plumbing that sits above the vdagent |
| `bin/antharchy-vm-doctor` | Session diagnostics — the thing you want at 2am |

## Two things here are host-specific, not VM-specific

Both must stay opt-in, because EC2 must not get either:

- **The keyboard swap** (`altwin:swap_lalt_lwin`) exists because macOS Screen Sharing keeps
  Command for itself, so Option has to become Super. That is a *macOS host* concern.
- **A fixed display mode** is right for a window on a Mac and wrong for a headless instance.

The environment drop-ins, by contrast, should be gated on `systemd-detect-virt` so a bare-metal
laptop never has software rendering forced on it.

## Not carried over

`install-antharchy-distribution.sh.reference` is kept for reading only. It was the pivot point of
the old builder — the first version that installed the distribution as packages instead of
reproducing it by hand — and its own comment records the packaging gap that motivated this
rebuild:

```
# The PKGBUILDs do not ship the full etc/ tree; copy what the ARM builder
# needs from the checkout that was used to build the packages.
```

`antharchy-bootstrap` supersedes it.

Everything else from that builder — the 15-tool source-build loop, the hardcoded `infra` and
`heavy` package lists, the tool contract, migration sealing, and the sanitize phase that the
`/usr/share/omarchy` symlink-into-`$HOME` made necessary — existed only because Arch Linux ARM
had no `antharchy` package. None of it survives.
