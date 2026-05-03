# opencode-profile

Switch between multiple OpenAI subscription accounts (ChatGPT Plus/Pro) in [OpenCode](https://opencode.ai).

OpenCode stores a single set of OAuth credentials per provider. This script lets you save multiple OpenAI auth profiles and swap between them via symlink.

## Install

Install it to a user-local bin directory:

```bash
mkdir -p ~/.local/bin
install -m 0755 opencode-profile ~/.local/bin/opencode-profile
```

Make sure `~/.local/bin` is on your `PATH`, then run `opencode-profile ...` from anywhere.

## Setup

```bash
# 1. Open opencode → /connect → OpenAI → ChatGPT Plus/Pro → sign in with account A
# 2. Save it as a profile
opencode-profile make work --current

# 3. Open opencode → /connect → OpenAI → ChatGPT Plus/Pro → sign in with account B
# 4. Save it as a profile
opencode-profile make personal --current
```

You now have two profiles. Switch between them anytime:

```bash
opencode-profile switch work
# restart opencode
```

## Commands

| Command | Description |
|---|---|
| `make <name> --current` | Save the current `auth.json` as a named profile and set it active |
| `make <name>` | Create an empty placeholder profile |
| `switch <name>` | Switch to a profile by repointing `auth.json` |
| `list` | List all profiles; the active one is marked `(active)` |
| `which` | Print the active profile name. If `auth.json` is still a regular file, it reports that no profile is active yet. |
| `rename <old> <new>` | Rename a profile |
| `delete <name>` | Delete a profile |
| `help` | Show help |

Aliases: `ls` for `list`, `rm` for `delete`, `mv` for `rename`.

## How it works

Profiles are stored as JSON files in `~/.local/share/opencode/profiles/`. The script turns `~/.local/share/opencode/auth.json` into a symlink pointing to the active profile. Switching just repoints the symlink. All non-OpenAI credentials (Anthropic, Copilot, etc.) are unaffected.

```
~/.local/share/opencode/
├── auth.json -> profiles/work.json   # symlink
└── profiles/
    ├── work.json
    └── personal.json
```

Since OpenCode reads auth at startup, you need to restart it after switching.

## Safety

- Cannot delete the last remaining profile
- Cannot delete the currently active profile
- Backs up `auth.json` automatically on first switch if it's a regular file
- Warns if OpenCode is running when you switch
- Validates profile names (alphanumeric, hyphens, underscores)

## Testing and CI

Run the local harness directly:

```bash
tests/opencode-profile.test.sh
```

GitHub Actions runs four checks on every push and pull request:

- `bash -n` syntax check
- `shellcheck`
- `shfmt -d`
- the deterministic shell test harness

## Note on token expiry

OAuth tokens expire. OpenCode refreshes the active profile's token automatically, but a saved profile you haven't used in a while may go stale. If that happens, switch to it, run `/connect` again in OpenCode, and re-save with `make <name> --current`.

## License

MIT
