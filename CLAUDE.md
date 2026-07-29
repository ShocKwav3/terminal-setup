# CLAUDE.md

Guidance for AI agents working in this repo. Kept lean on purpose — this file is
the **guardrails**. The "how it's built / how to change each area" reference lives
in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md); read the relevant section there
before changing the installer internals, the testing setup, or the starship / yazi
configs.

## What this is

A single-file macOS terminal-setup installer. `install.sh` bootstraps a fresh Mac
(Xcode CLT → Homebrew → figlet), then walks **five segments**, each prompting
before it acts:

1. **Terminal** — wezterm + the tools its config hard-depends on + configs.
2. **Shell** — oh-my-zsh + everything `.zshrc` integrates + the `.config/*` configs.
3. **Git** — identity + optional SSH key + git-delta, via `git config --global`.
4. **Claude Code** — native installer + plugins + node shim + `~/.claude/settings.json`.
5. **Agent tooling** — herdr + hunk + `~/.config/herdr`; agent-CLI-agnostic, so the
   herdr integration target (claude / codex / opencode / …) is **prompted for**, never
   assumed. Runs after Claude so `herdr integration install claude` edits a
   `~/.claude/settings.json` that has already been deployed.

Config-bearing shell/terminal tools install **and** configure together (the configs
assume the tools), so those segments are all-or-nothing. The installer holds **no**
user config inline — configs live in `configs/` and are copied at deploy time. (The
node shim is the one exception: installer infrastructure, generated inline.)

## Layout

```
install.sh            # the whole installer (bash 3.2-safe, no associative arrays)
configs/
  home/               # → $HOME
    .zshrc  .wezterm.lua          # NO .gitconfig — git is set via `git config --global`
  config/             # → $HOME/.config
    atuin/ bat/ fastfetch/ starship/
    yazi/             # init.lua (BIOS chrome) + 3 vendored bios flavors
    herdr/            # config.toml only — session/log/lock files are runtime state
  claude/             # → $HOME/.claude
    settings.json                 # portable: no hooks block, no absolute paths
docs/DEVELOPMENT.md   # function map, testing patterns, starship/yazi internals, target facts
```

## Hard rules

- **Single file.** All installer logic stays in `install.sh`. Do not split into
  multiple scripts or add a lib dir.
- **bash 3.2 compatible.** macOS default `/bin/bash` is 3.2.57. No `declare -A`
  (associative arrays), no `${var^^}`, no `mapfile`/`readarray`. Indexed arrays OK.
  Verify with `/bin/bash -n install.sh`.
- **Idempotent.** Every install step checks existence first and skips if present.
  Re-running must never reinstall or silently overwrite anything.
- **Configs are never clobbered silently.** Each config goes through `deploy`,
  which prompts `keep / overwrite / diff` when the destination already exists;
  overwrite backs up to `<dest>.bak.<timestamp>` first.
- **Edit configs under `configs/`, not `~`.** `configs/` is the source of truth
  (seeded from a live machine). Keep junk out: no `.DS_Store`, `*.bak`, `.git`
  dirs, or theme `preview.png` / `README.md`.
- **Claude Code config is in scope; `opencode` is not.** `configs/claude/settings.json`
  is vendored (portable: no `hooks` block, no absolute paths — caveman runs via its
  plugin + the node shim). `opencode` stays excluded. `ccstatusline` needs no vendored
  file (it's invoked via `bunx` from `settings.json`).
- **No `.gitconfig` is vendored.** Git identity, the optional SSH key, and git-delta
  are applied with `git config --global` / `ssh-keygen` so the target machine's own
  git policy is preserved — we only add our keys. Never add a `configs/home/.gitconfig`.
- **node shim.** `install_node_shim` writes `~/.local/bin/node` (resolves the newest
  nvm node at call time) so non-interactive `/bin/sh` hooks — e.g. Claude/caveman —
  can find `node`, which `.zshrc` only exposes as a lazy interactive function.

## Testing (must stay non-destructive)

Before every commit:

```bash
bash -n install.sh && /bin/bash -n install.sh        # syntax + 3.2 compat
```

Never run the installer or its functions against the real `$HOME`. Drive them
against a `mktemp -d` via `INSTALL_HOME`, stub `brew`/`curl`/`claude`, and override
`HOME`/`GIT_CONFIG_GLOBAL` for the git steps. Full patterns + per-feature test
recipes (starship transform, yazi picker, yazi `init.lua` pty check) are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#testing-must-stay-non-destructive).
