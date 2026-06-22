# CLAUDE.md

Guidance for AI agents working in this repo.

## What this is

A single-file macOS terminal-setup installer. Running `install.sh` bootstraps a
fresh Mac (Xcode CLT → Homebrew → figlet) then walks **four segments**, each
prompting before it acts:

1. **Terminal** — wezterm + the tools its config hard-depends on (fonts, blueutil,
   fastfetch) + `.wezterm.lua` / fastfetch config.
2. **Shell** — oh-my-zsh + everything `.zshrc` integrates (starship, atuin, bat,
   eza, zoxide, fzf, fd, ripgrep, jq, yazi+deps, terminal-notifier, runtimes incl.
   node + the node shim, fzf-git) + the `.config/*` configs.
3. **Git** — identity + optional SSH key + git-delta, applied via `git config
   --global` (no `.gitconfig` is copied).
4. **Claude Code** — native installer + plugins (via `claude plugin`) + node shim
   + `~/.claude/settings.json`.

Config-bearing shell/terminal tools install **and** configure together (the configs
assume the tools), so those two segments are all-or-nothing. The installer holds
**no** user config inline — configs live in `configs/` and are copied at deploy
time. (The node shim is the one exception: installer infrastructure, generated
inline, not a user config.)

## Layout

```
install.sh            # the whole installer (bash 3.2-safe, no associative arrays)
configs/
  home/               # → $HOME
    .zshrc  .wezterm.lua          # NO .gitconfig — git is set via `git config --global`
  config/             # → $HOME/.config
    atuin/ bat/ fastfetch/ starship/ yazi/
  claude/             # → $HOME/.claude
    settings.json                 # portable: no hooks block, no absolute paths
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

## install.sh structure (function map)

- Output helpers: `info ok warn err step summary banner confirm`
- `prompt_choice "q" <default> <other>` — two-way picker, result in `REPLY_CHOICE`
- `record <installed|configured|skipped> <item>` — appends to the `REC_*` summary arrays
- Detection: `have brew_installed cask_installed`
- `brew_formulae <pkg...>` / `brew_casks <pkg...>` — install the missing ones, record them
- Bootstrap: `ensure_xcode_clt ensure_homebrew ensure_figlet`
- Runtimes: `ensure_nvm ensure_node install_node_shim ensure_bun ensure_uv`
  (`ensure_node` installs an LTS node — nvm alone provides no node — then the shim)
- Shell helpers: `ensure_omz install_omz_plugins install_fzf_git`
- Deploy: `deploy <src> <dest>`, `show_diff`
- Segments: `segment_terminal segment_shell segment_git segment_claude`
  - git uses `configure_git` (identity + `diff.colorMoved` + optional SSH key) and
    `configure_git_delta` (4 `git config --global` lines incl. `merge.conflictStyle zdiff3`)
- `apply_starship_variants` — prompts for the two starship axes and rewrites the
  deployed `starship.toml` with an `awk` pass (see "starship prompt variants" below).
  Runs inside the Shell segment's configure step.
- `final_summary` — figlet "All Done" banner + Installed/Configured/Skipped list + next steps
- `main` — bootstrap, then the four segments, then `final_summary`

`DEST_HOME`/`DEST_CONFIG` honor `INSTALL_HOME` env override for safe testing.

## Testing (must stay non-destructive)

```bash
bash -n install.sh && /bin/bash -n install.sh        # syntax + 3.2 compat
```

To test deploy/segment logic, never point at the real `$HOME`. Source the functions
and drive them against a `mktemp -d`, feeding prompt answers on stdin, then `rm -rf`
the temp dir. Pattern: strip the trailing `main "$@"`, source the rest, override
`CONFIGS_DIR`/`DEST_HOME`/`DEST_CONFIG`, call a `segment_*` with piped input.

Segments call `brew`/`curl`/`claude` (network/installs) — stub them on a temp `PATH`
(a fake `brew` whose `list` exits 0 so everything reads as "already installed", a
fake `claude`, etc.) and pre-seed the temp `$HOME` (`.nvm/versions/node/*`, `.bun`,
`.oh-my-zsh`, …) so install steps short-circuit. The git/SSH/delta steps use
`git config --global` + `ssh-keygen`, which hit the **real** `$HOME` regardless of
`INSTALL_HOME` — override `HOME` (and `GIT_CONFIG_GLOBAL`) to the temp dir so the
real `~/.gitconfig` / `~/.ssh` are never touched.

To test the starship transform, copy `starship.toml` into a temp `DEST_CONFIG`,
run `apply_starship_variants` with stdin answers, and verify the result with
`STARSHIP_CONFIG=<file> starship print-config`. Check all four combos; the
`colorful + icon` output must be byte-identical to the repo copy, and re-running
the transform on its own output must be a no-op (idempotent).

## Editing configs

`configs/` is seeded from a live machine. When updating a config, edit the file
under `configs/`, not `~`. Keep junk out: no `.DS_Store`, no `*.bak`, no `.git`
dirs, no theme `preview.png` / `README.md`.

### starship prompt variants

`configs/config/starship/starship.toml` ships in its **canonical** form:
**colorful + icon-only**. Every module that can vary carries its alternates as
commented blocks, each introduced by a fixed marker line:

- `# v1 (orig colorful — ACTIVE...)` — colorful, icon-only *(active in the repo)*
- `# v2 (less-color icon-only — INACTIVE):` — grey/dim, icon-only
- `# --- verbose (version) below ... ---` — colorful, icon + version
- `# v4 (less-color verbose — INACTIVE):` — grey/dim, icon + version

Toolchain modules (the ones with a `# command = ...` line: `pkg_*`, `cmake`,
`lang_*`, `runtime_*`, `fw_*`, `test_*`) have all four. Color-only modules
(`username`, `directory`, `cmd_duration`, `env_var`, `container`, `docker_context`,
`terraform`, `helm`, `kubernetes`, `status`) have only `v1`/`v2` — the verbose axis
falls back to the matching icon variant for them. The `git_*` modules are fixed
(no markers). wezterm has **no** variants.

`apply_starship_variants` maps the two prompt answers to one target marker per
module (colorful+icon→v1, lesscolor+icon→v2, colorful+verbose→verbose,
lesscolor+verbose→v4), then for each module uncomments the target block, comments
the others, and toggles the `# command` line (on only for verbose). It works from
the canonical baseline every run, so it is deterministic and idempotent.

**Rules when editing this file:**
- Keep the marker lines verbatim — the installer's `awk` matches on them.
- The default-active block must stay **uncommented** and be `v1` (colorful+icon);
  all other blocks stay `# `-commented. `command` stays commented by default.
- A multiline `format` value's body lines start with `[`; the `awk` only treats a
  bare `[name]` line as a table header, so don't put a real value on a line that
  looks like a header.
- If you add a new toolchain module, give it all four blocks (the `v4` block mirrors
  the verbose block but uses `color_grey` bg + `color_dim_white` text).
- Test the transform non-destructively (see Testing) for all four combos.

### yazi flavors

Flavors are vendored (copied in full), so no `ya pkg` step at install time. Only
the **active** flavor is kept. Active flavor is set in `configs/config/yazi/theme.toml`
(`[flavor] dark = "..."`). Currently `bluloco-dark`. If you change the active
flavor: add its dir under `flavors/<name>.yazi` (just `flavor.toml` + `tmtheme.xml`
+ LICENSE), update `theme.toml`, update `package.toml`'s `[[flavor.deps]]`, and
delete the old flavor dir.

## Key facts about the target setup

- Shell: zsh + oh-my-zsh, prompt via **starship** (not p10k).
- omz custom plugins cloned: `zsh-autosuggestions`, `fast-syntax-highlighting`.
- `.zshrc` sources `~/Documents/Tools/fzf-git.sh/fzf-git.sh` (installer clones it).
- Aliases redefine `ls`→eza, `cat`→bat, `cd`→zoxide `z`.
- Terminal: wezterm; font: **MesloLGS Nerd Font** (from `font-meslo-lg-nerd-font`).
- bat uses a custom `tokyonight_night` theme → `bat cache --build` required post-deploy.
