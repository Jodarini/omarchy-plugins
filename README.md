# omarchy-plugins

My Omarchy shell plugins in one repo, synced across every machine.

On each PC this repo **is** `~/.config/omarchy/plugins`. The Omarchy shell
watches that folder with inotify, so when a pull rewrites a plugin's files the
plugin hot-reloads. You don't need to restart anything.

| Plugin | What it does |
|---|---|
| [`jodarini.downloads`](jodarini.downloads) | Recent downloads in the bar, in a window you can drag files out of (from [Downloadini](https://github.com/Jodarini/Downloadini), history included) |

## Set up a machine

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Jodarini/omarchy-plugins/main/.sync/install.sh)
```

The installer:

- turns `~/.config/omarchy/plugins` into a checkout of this repo. Any plugin
  already there that this repo also ships (e.g. an old standalone
  `jodarini.downloads` clone) gets moved to `~/.config/omarchy/plugins.backup.*`.
  Other plugins aren't touched.
- links `~/.local/bin/omarchy-plugins`
- turns on a systemd user timer that syncs 1 minute after login and then
  every 10 minutes

Plugin ids don't change, so plugins you already enabled stay enabled. For a
plugin new to that machine, run `omarchy plugin enable <id>` once.

## Day to day

Edit a plugin in place in `~/.config/omarchy/plugins/<id>`. It reloads live.
When it works:

```bash
omarchy-plugins push "Tweak downloads row height"   # message optional
```

The other machines pick it up within 10 minutes. To pull right away, run
`omarchy-plugins sync`.

| Command | |
|---|---|
| `omarchy-plugins sync` | fetch, fast-forward, push committed work, reload the shell |
| `omarchy-plugins push [msg]` | commit all changes and sync |
| `omarchy-plugins status` | local changes, ahead/behind, timer state |
| `omarchy-plugins import <git-url> [id]` | bring in an existing plugin repo with its history |
| `omarchy-plugins auto on\|off` | toggle the auto-sync timer |
| `omarchy-plugins log` | recent auto-sync runs |

Auto-sync never commits for you. Half-finished edits stay local until you
`push`. If an upstream change touches a file you've edited but not committed,
or a rebase conflicts, sync stops and sends a desktop notification. Nothing
gets overwritten.

## Adding a plugin

Make a folder named after the plugin id (`jodarini.<name>/` with a
`manifest.json`), or start from a built-in with
`omarchy plugin clone <source-id>`. Then run `omarchy-plugins push`.

`.gitignore` ignores everything at the top level except `jodarini.*/`, so
third-party plugins installed with `omarchy plugin add` stay out of the repo.
A plugin of mine with a different id needs a `!/<id>/` line in `.gitignore`.
