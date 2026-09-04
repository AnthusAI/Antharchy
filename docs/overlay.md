# The overlay

How Antharchy is expressed as a delta against Omarchy, and the rules for changing it.

## The four shapes a change can take

Pick by what the change *is*, not by what is convenient.

| Change | Mechanism | Fails when |
|---|---|---|
| A few lines inside an upstream file | `patches/NNNN-*.patch` + a line in `patches/series` | upstream edits the surrounding context |
| An upstream file removed | a line in `delete.list` | upstream already removed it |
| An upstream file we take over entirely | `overlay/<path>` + `replace` in `overlay.map` | upstream renames or deletes it |
| A file that is ours alone | `overlay/<path>` + `new` in `overlay.map` | upstream starts shipping that path |

Each failure is a build error naming the path. That is the whole design: the overlay is a set of
claims about upstream, and every claim is checked on every build.

## The growth rule

**A patch that grows past a few hunks stops being a patch and becomes a `replace`.**

A small patch is reviewable as a diff and pins us to upstream's structure in a useful way. A large
one is neither: it conflicts on every upstream edit to the file, including edits to lines we do
not care about, and nobody can read it. When a patch reaches that point, move the whole file into
`overlay/` and mark it `replace`.

The reverse also holds. A `replace` whose content is identical to upstream is a lie — it claims to
change something and does not. Delete it. (`logo.svg` is deliberately *absent* from `overlay/` for
this reason: it is still upstream's wordmark and we have no replacement yet.)

## Why not sed

Scripted edits were considered and rejected for the surgical case. `sed -i '/kdenlive/d'` silently
does nothing when upstream renames the package, and silently deletes the wrong line when upstream
adds a second match. Both failures are invisible until a user's desktop is wrong. `git apply` with
zero fuzz fails instead, which is the entire point.

## Why patches never see overlay output

`apply-overlay.sh` applies patches to the **pristine** upstream tree, before any overlay file is
copied in. A patch written against upstream context that landed on our replacement would apply
cleanly and mean something different.

## Two nets, not one

`git apply` catches *syntactic* drift: the context a patch expected has moved.

It cannot catch *semantic* drift. If upstream adds a new `app.hey.com` reference in a new file,
every patch still applies and Antharchy silently ships a HEY binding again. So
`tools/verify-overlay.sh` scans the finished tree for upstream identity that should not have
survived, and the build fails on any unexempted hit.

Exemptions live in that script's `EXEMPT` array and each carries a comment saying why. Prefer an
exact path over a directory: two upstream migrations are exempted individually so that a *future*
migration referencing upstream still fails the build.

There is a third net for a failure mode we actually hit: after patching, every patched file is
compared against upstream and the build fails if one is byte-identical. `git apply` can report
success while changing nothing — it does exactly that when it discovers a surrounding git
repository and resolves paths against that repo's root instead of the tree. Success is verified,
not trusted.

## Project constants

Values that appear in more than one shipped file — the package domain, the signing key
fingerprint, the project URLs — are defined once in [`project.conf`](../project.conf) and written
as `@@TOKEN@@` in overlay files. `apply-overlay.sh` substitutes them and fails on any placeholder
it cannot resolve.

Substitution is scoped to the paths *we* ship. Upstream has its own `@@TOKEN@@` templates —
`default/limine/default.conf` carries `@@CMDLINE@@` for the ISO to fill in at install time — and
rewriting or erroring on those would corrupt files we do not own.

## Bumping upstream

```bash
tools/bump-upstream.sh <sha|tag>
```

It runs `--check` against the new commit first and reports which patches no longer apply, so a
bump is a decision rather than a surprise. `git apply -3` is never used automatically: a
three-way merge can succeed on a semantically wrong hunk, which is the one outcome this whole
mechanism exists to prevent.

`install/omarchy-base.packages` and `bin/omarchy-provision-user` are actively edited upstream and
are the patches most likely to need attention.

## Known gaps

- **The pacman channel templates are aarch64-only.** They describe Arch Linux ARM's repo set and
  omit upstream's package repo, which publishes no ARM tree. Per-architecture generation belongs
  in the PKGBUILDs, since the package is arch-split.
- **Three upstream tests cannot pass here.** `version-test.sh`, `channel-test.sh` and
  `update-available-test.sh` assert upstream's package names and its `-dev` package pair, neither
  of which Antharchy has. `test/antharchy.d/identity-test.sh` covers the model we do have;
  adapting or replacing those three is outstanding.
