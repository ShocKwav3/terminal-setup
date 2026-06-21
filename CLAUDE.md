# CLAUDE.md

Guidance for AI agents working in this repo.

## What this is

A single-file macOS terminal-setup installer. Running `install.sh` provisions a
fresh Mac: installs CLI tools / runtimes / fonts / shell plugins (checking first,
prompting before each), then deploys the config files in `configs/` to `$HOME` and
`$HOME/.config`. The installer holds **no** config inline — configs live in
`configs/` and are copied at deploy time.

## Layout

```
install.sh            # the whole installer (bash 3.2-safe, no associative arrays)
configs/
  home/               # → $HOME
    .zshrc  .wezterm.lua  .gitconfig   # .gitconfig has NO [user] section
  config/             # → $HOME/.config
    atuin/ bat/ fastfetch/ starship/ yazi/
```

## Hard rules

- **Single file.** All installer logic stays in `install.sh`. Do not split into
  multiple scripts or add a lib dir.
- **bash 3.2 compatible.** macOS default `/bin/bash` is 3.2.57. No `declare -A`
  (associative arrays), no `${var^^}`, no `mapfile`/`readarray`. Indexed arrays OK.
  Verify with `/bin/bash -n install.sh`.
- **Idempotent.** Every install step checks existence first and skips if present.
  Re-running must never reinstall or silently overwrite anything.
- **Configs are never clobbered silently.** Deploy is gated by one top-level confirm,
  then per-file `keep / overwrite / diff`. Overwrite backs up to
  `<dest>.bak.<timestamp>` first.
- **No Claude Code / AI-tool configs.** `opencode` and `ccstatusline` are
  deliberately excluded from `configs/` (Claude Code-related, out of scope).
- **`.gitconfig` identity is prompted, not stored.** The repo copy has the `[user]`
  section stripped; `install.sh` prompts for name/email and writes them via
  `git config --global`. Never commit a name/email into `configs/home/.gitconfig`.

## install.sh structure (function map)

- Output helpers: `info ok warn err step summary banner confirm`
- Detection: `have brew_installed cask_installed`
- Bootstrap: `ensure_xcode_clt ensure_homebrew ensure_omz`
- `ensure_runtimes` — nvm / bun / uv (curl installers, not brew)
- `ensure_formulae "<summary>" <pkg...>` / `ensure_casks ...` — grouped brew installs
- `install_formulae install_casks install_omz_plugins install_fzf_git`
- Deploy: `deploy <src> <dest>`, `show_diff`, `configure_git_identity`, `deploy_configs`
- `prompt_choice "q" <default> <other>` — two-way picker, result in `REPLY_CHOICE`
- `apply_starship_variants` — prompts for the two starship axes and rewrites the
  deployed `starship.toml` with an `awk` pass (see "starship prompt variants" below)
- `post_install` — `bat cache --build` + final notes
- `main` — runs the phases in order

`DEST_HOME`/`DEST_CONFIG` honor `INSTALL_HOME` env override for safe testing.

## Testing (must stay non-destructive)

```bash
bash -n install.sh && /bin/bash -n install.sh        # syntax + 3.2 compat
```

To test deploy logic, never point at the real `$HOME`. Source the functions and
drive them against a `mktemp -d`, feeding prompt answers on stdin, then `rm -rf`
the temp dir. Example pattern: strip the trailing `main "$@"`, source the rest,
override `CONFIGS_DIR`/`DEST_HOME`/`DEST_CONFIG`, call `deploy` with piped input.

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
