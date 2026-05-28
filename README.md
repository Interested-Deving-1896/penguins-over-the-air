# penguins-over-the-air

Debian/Devuan fork of [linux-over-the-air](https://github.com/Interested-Deving-1896/linux-over-the-air).

Adds Debian-family tuning, fwupd hooks, and [penguins-eggs](https://github.com/pieroproietti/penguins-eggs) ISO lifecycle integration on top of the upstream OTA engine.

## What's different from linux-over-the-air

| Feature | linux-over-the-air | penguins-over-the-air |
|---|---|---|
| Default distro | generic | debian |
| APT pre-flight | — | ✓ broken package check, LVFS refresh |
| fwupd policy | configurable | before_os (Debian default) |
| unattended-upgrades | — | ✓ respected |
| MOK enrollment | — | ✓ `fwupd-debian.sh mok-enroll` |
| penguins-eggs | — | ✓ post-update ISO rebuild hook |
| Waydroid channel | configurable | vanilla (default) |
| Halium distro | configurable | droidian (default) |

## Quick start

```bash
# Install
apt-get install penguins-over-the-air

# Configure
cp /usr/share/pota/system.toml /etc/pota/system.toml
$EDITOR /etc/pota/system.toml

# Check for update
pota update --check-only

# Apply update
pota update
```

## penguins-eggs integration

```toml
# /etc/pota/system.toml
[penguins_eggs]
enabled = true
rebuild_iso_on_update = true   # rebuild ISO after each OTA
iso_output_dir = "/home/eggs"
```

After a successful OTA update, `eggs produce --nointeractive` runs automatically
to produce an updated live/installable ISO.

## fwupd on Debian

fwupd is enabled by default with `policy = "before_os"`. The Debian-specific
wrapper respects `/etc/apt/apt.conf.d/50unattended-upgrades` and runs
`needrestart` after firmware updates.

```bash
# Check firmware update status
pota-fwupd status

# Apply firmware updates manually
pota-fwupd apply-debian

# Enroll a new Secure Boot MOK key
pota-fwupd mok-enroll /path/to/key.pem
```

## Upstream sync

```bash
git remote add upstream https://github.com/Interested-Deving-1896/linux-over-the-air
git fetch upstream
git merge upstream/main
```

## License

Apache-2.0
