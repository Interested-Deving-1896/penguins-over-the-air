# AGENTS.md — penguins-over-the-air

Guidance for AI agents working in this repository.

## Repository purpose

Debian/Devuan-tuned fork of linux-over-the-air. Adds:
- Debian-specific bootloader and APT integration
- fwupd hooks with Debian policy awareness (unattended-upgrades, MOK enrollment)
- penguins-eggs ISO lifecycle integration
- Waydroid support tuned for Debian hosts (vanilla channel default)
- Halium support for Droidian

This repo is a **downstream fork** — do not duplicate logic from linux-over-the-air.
Add only Debian-specific overrides and hooks.

## Relationship to linux-over-the-air

```
linux-over-the-air (upstream)
  └── penguins-over-the-air (this repo, Debian fork)
        └── penguins-eggs all-features branch (consumer)
```

When linux-over-the-air gains new features, merge them here with:
```bash
git remote add upstream https://github.com/Interested-Deving-1896/linux-over-the-air
git fetch upstream
git merge upstream/main
```

## Debian-specific additions

| Path | Purpose |
|---|---|
| `runtime/debian/apt-preflight.sh` | APT state check + LVFS refresh before OTA |
| `runtime/debian/eggs-hook.sh` | penguins-eggs ISO lifecycle integration |
| `runtime/firmware/fwupd-debian.sh` | Debian fwupd wrapper (unattended-upgrades, MOK) |
| `config/system.toml` | Debian-tuned defaults (`[penguins_eggs]`, `[firmware.debian]`) |

## Hook installation

Default hooks installed to `/etc/pota/hooks.d/`:

```
pre-install-10-apt-preflight.sh  → runtime/debian/apt-preflight.sh preflight
pre-install-20-fwupd-pre.sh      → runtime/firmware/fwupd-debian.sh pre-os-update
post-install-10-fwupd-post.sh    → runtime/firmware/fwupd-debian.sh post-os-update
post-reboot-10-eggs.sh           → runtime/debian/eggs-hook.sh post-update
```

## penguins-eggs integration

penguins-eggs is an optional post-update hook. Enable ISO rebuilding:

```toml
# /etc/pota/system.toml
[penguins_eggs]
enabled = true
rebuild_iso_on_update = true
iso_output_dir = "/home/eggs"
```

The hook calls `eggs produce --nointeractive` after a successful OTA update.

## fwupd Debian policy

`runtime/firmware/fwupd-debian.sh` wraps the base `fwupd-coordinator.sh` and:
1. Checks `/etc/apt/apt.conf.d/50unattended-upgrades` for fwupd blocks
2. Applies plugin allowlist from `[firmware.debian].plugin_allowlist`
3. Runs `needrestart -r a` after firmware updates
4. Provides `mok-enroll` for Secure Boot key enrollment

## Waydroid on Debian

Default channel is `vanilla` (AOSP without GApps) — appropriate for Debian's
privacy-first defaults. Switch to `gapps` in system.toml if needed.

Incus integration for Waydroid LXC management is opt-in (`use_incus = true`).

## Commit conventions

Same as linux-over-the-air: conventional commits with `(debian):` scope for
Debian-specific changes. Example: `feat(debian): add MOK enrollment hook`.

## Testing

```bash
# APT preflight
bash runtime/debian/apt-preflight.sh check

# fwupd Debian status
bash runtime/firmware/fwupd-debian.sh status

# eggs hook status
bash runtime/debian/eggs-hook.sh status

# Shell lint
find runtime/ -name '*.sh' | xargs shellcheck --severity=warning
```
