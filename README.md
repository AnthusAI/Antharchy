# Antharchy ⚡

**Antharchy** is a beautiful, modern & agentic Arch Linux desktop distribution by
[Anthus AI](https://github.com/AnthusAI), built for AI-assisted engineering and cloud development.

Based on [Omarchy](https://github.com/omacom/omarchy) — [Hyprland](https://hyprland.org/),
[Quickshell](https://quickshell.org/) and [UWSM](https://github.com/Vladimir-csp/uwsm) — and
customized for high-efficiency development workflows with Claude, Claude Code, and modern tooling.

---

## This repository is an overlay, not a distribution tree

There is no copy of Omarchy here. This repository contains **only** what makes Antharchy
different from it, plus a pinned upstream commit, and a tool that combines the two:

| | |
|---|---|
| [`upstream.lock`](upstream.lock) | the exact Omarchy commit we build from |
| [`patches/`](patches/) | surgical edits to upstream files |
| [`overlay/`](overlay/) | whole files we own outright |
| [`delete.list`](delete.list) | upstream files we remove |
| [`overlay.map`](overlay.map) | classifies every overlay file `replace` or `new` |
| [`tools/apply-overlay.sh`](tools/apply-overlay.sh) | the only thing that builds a tree |

Antharchy was previously a full-tree fork: a complete copy of the Omarchy repository in which
21 files out of roughly 1,500 differed. Every upstream release had to be merged by hand, and the
99% that was identical made the 1% that mattered impossible to see. That history is preserved at
the `v0-fulltree` tag.

To build a tree:

```bash
tools/apply-overlay.sh --into build/src
```

To check the overlay still applies without writing anything:

```bash
tools/apply-overlay.sh --check
```

See [docs/overlay.md](docs/overlay.md) for how the mechanism works and when to use each part.

## Why an overlay fails loudly

A plain "copy our files over theirs" overlay succeeds forever. It succeeds when upstream deletes
the file you were overriding, and it succeeds when upstream starts shipping a file at a path you
thought was yours. You find out months later, from a user.

So every overlay path is classified. `replace` asserts the file **is** in upstream; `new` asserts
it **is not**. Patches apply with zero fuzz and are then verified to have actually changed the
tree. A scan of the finished tree catches upstream identity that survived — the case no patch can
catch, because the reference is in a file upstream only added last week.

## Status

Rebuild in progress. Phase 1 (overlay skeleton) is complete and verified; packaging, the
package repository, and the Lima VM follow. ARM (aarch64) is the lead target.

## Running locally on Apple Silicon

Antharchy is a Linux desktop, not a macOS app. On an Apple Silicon Mac it runs in a Lima VM —
Arch Linux ARM with Hyprland on virtio-gpu. See [`lima/`](lima/).

## License

MIT. Derived from [Omarchy](https://github.com/omacom/omarchy), also MIT.
