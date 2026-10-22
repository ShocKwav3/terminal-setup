# DEVELOPMENT.md

Reference detail for agents working on the installer. The **invariants you must
not break** live in [`../CLAUDE.md`](../CLAUDE.md) (Hard rules) — this file is the
"how it's built / how to change it" companion. Read the relevant section here
before touching the installer, the testing setup, or the starship / yazi configs.

## install.sh structure (function map)

- Output helpers: `info ok warn err step summary banner confirm`
- `prompt_choice "q" <default> <other>` — two-way picker, result in `REPLY_CHOICE`
- `record <installed|configured|skipped> <item>` — appends to the `REC_*` summary arrays
- Detection: `have brew_installed cask_installed`
- `brew_formulae <pkg...>` / `brew_casks <pkg...>` — install the missing ones, record them
- Bootstrap: `ensure_xcode_clt ensure_homebrew ensure_figlet`. `ensure_homebrew`
  also picks up an off-PATH `/opt/homebrew/bin/brew` and calls
  `persist_brew_shellenv`, which appends `eval "$(/opt/homebrew/bin/brew shellenv)"`
  to `$DEST_HOME/.zprofile` unless `/etc/paths(.d)` already lists `/opt/homebrew/bin`
  or the line exists (Homebrew's script installer only prints this step; without it
  new login shells — incl. wezterm's `zsh -l -c fastfetch` — can't find brew tools).
- `main` prepends `~/.local/bin` to `PATH` for the run, since the curl installers
  (claude, herdr, uv tools) land there and a fresh Mac's PATH lacks it.
- Runtimes: `ensure_nvm ensure_node install_node_shim ensure_bun ensure_uv`
  (`ensure_node` installs an LTS node — nvm alone provides no node — then the shim)
- `npm_global <pkg> <bin>` — `npm install -g` into the newest `~/.nvm/versions/node/*`
  (npm is never on a non-interactive PATH, so it is resolved the way the node shim
  does). Used for `pnpm` (Shell) and `hunkdiff` (Agent tooling).
- `uv_tool <bin> <python|""> <spec>` — `uv tool install` into `~/.local/bin`, skipped
  if `<bin>` exists. Used for `headroom` (`headroom-ai[all]`, python 3.13) and
  `skillspector` (git+https NVIDIA/skillspector).
- Shell helpers: `ensure_omz install_omz_plugins install_fzf_git`
- Deploy: `deploy <src> <dest>`, `show_diff`
- Segments: `segment_terminal segment_shell segment_git segment_claude segment_agent_tools`
  - git uses `configure_git` (identity + `diff.colorMoved` + optional SSH key) and
    `configure_git_delta` (4 `git config --global` lines incl. `merge.conflictStyle zdiff3`).
    `segment_git` counts git as present only when `xcode-select -p` succeeds or brew's
    `git` is installed — a fresh Mac's `/usr/bin/git` is a CLT-installer stub.
  - claude runs `ensure_node` + `ensure_bun` (statusLine is `bunx ccstatusline`), then
    deploys `settings.json` + `~/.config/ccstatusline` **before** the marketplace /
    plugin installs — `claude plugin install` creates settings.json, which would turn
    a fresh deploy into a keep/overwrite prompt.
  - agent tools use `install_herdr` (curl `herdr.dev/install.sh` → `~/.local/bin/herdr`),
    `npm_global hunkdiff hunk`, `install_rtk` (brew `rtk`, skipped if any `rtk` is
    already present), the two `uv_tool` calls, then three wiring steps:
    `install_herdr_integration` (prompts for the agent CLI target and runs
    `herdr integration install <target>`; empty input skips),
    `install_rtk_integration` (same prompt pattern → `rtk init -g --agent <target>`,
    or `--codex`/`--copilot`/`--gemini`) and `install_headroom_mcp` (confirm, then
    `claude mcp add --scope user headroom -- ~/.local/bin/headroom mcp serve`; skipped
    when `claude mcp get headroom` succeeds)
- `apply_starship_variants` — prompts for the two starship axes and rewrites the
  deployed `starship.toml` with an `awk` pass (see "starship prompt variants" below).
  Runs inside the Shell segment's configure step.
- `apply_yazi_bios_theme` — prompts for one of the three BIOS looks (mega/laurel/
  firebird) and overwrites the deployed `yazi/theme.toml`'s `dark = "..."` (see
  "yazi BIOS themes" below). Same guard as starship: only touches a theme.toml that
  still byte-matches the repo baseline. Also runs in the Shell segment's configure step.
- `final_summary` — figlet "All Done" banner + Installed/Configured/Skipped list + next steps,
  then `optional_extras` (a printed-only reminder of tools deliberately not installed,
  each with its install command — add to that list rather than to a segment for
  project-specific tools)
- `main` — bootstrap, then the five segments, then `final_summary`

`DEST_HOME`/`DEST_CONFIG` honor `INSTALL_HOME` env override for safe testing.

## Testing (must stay non-destructive)

```bash
bash -n install.sh && /bin/bash -n install.sh        # syntax + 3.2 compat
```

To test deploy/segment logic, never point at the real `$HOME`. Source the functions
and drive them against a `mktemp -d`, feeding prompt answers on stdin, then `rm -rf`
the temp dir. Pattern: strip the trailing `main "$@"`, source the rest, override
`CONFIGS_DIR`/`DEST_HOME`/`DEST_CONFIG`, call a `segment_*` with piped input.

> Note: the Bash tool's shell is zsh, which lacks `BASH_SOURCE`. Run these tests
> under `/bin/bash -c '...'`. Sourcing re-runs the script's top-level path
> assignments, so set `INSTALL_HOME` **before** sourcing and re-apply any
> `CONFIGS_DIR`/`DEST_CONFIG` override **after** — otherwise a function silently
> targets your real `~/.config`.

Segments call `brew`/`curl`/`claude` (network/installs) — stub them on a temp `PATH`
(a fake `brew` whose `list` exits 0 so everything reads as "already installed", a
fake `claude`, etc.) and pre-seed the temp `$HOME` (`.nvm/versions/node/*`, `.bun`,
`.oh-my-zsh`, …) so install steps short-circuit. The git/SSH/delta steps use
`git config --global` + `ssh-keygen`, which hit the **real** `$HOME` regardless of
`INSTALL_HOME` — override `HOME` (and `GIT_CONFIG_GLOBAL`) to the temp dir so the
real `~/.gitconfig` / `~/.ssh` are never touched.

`segment_agent_tools` has the same hazard, one level out: `install_herdr_integration`
shells out to the real `herdr`, which rewrites the target agent's own config (for
`claude`, `~/.claude/settings.json`) in the **real** `$HOME` no matter what
`INSTALL_HOME` says. Stub `herdr` on the temp `PATH` (a script that echoes its args
and exits 0) before driving that segment, or answer its prompt with an empty line to
take the skip path. The same goes for `install_rtk_integration` (`rtk init -g` edits
the real `~/.claude/settings.json` + `~/.claude/CLAUDE.md`) and `install_headroom_mcp`
(`claude mcp add` edits the real `~/.claude.json`): stub `rtk` and `claude` too.

To test the starship transform, copy `starship.toml` into a temp `DEST_CONFIG`,
run `apply_starship_variants` with stdin answers, and verify the result with
`STARSHIP_CONFIG=<file> starship print-config`. Check all four combos; the
`colorful + icon` output must be byte-identical to the repo copy, and re-running
the transform on its own output must be a no-op (idempotent).

To test the yazi theme picker, copy the repo `yazi/theme.toml` into a temp
`DEST_CONFIG/yazi/`, run `apply_yazi_bios_theme` with a stdin answer (``/`1`/`2`/`3`),
and check the resulting `dark = "..."`. Confirm the guard: a theme.toml that differs
from the repo baseline is left untouched. To test `init.lua` chrome, drive yazi in a
pty (see "yazi BIOS themes").

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
(`username`, `directory`, `cmd_duration`, `env_var`, `container`, `custom.docker`,
`terraform`, `helm`, `kubernetes`, `status`) have only `v1`/`v2` — the verbose axis
falls back to the matching icon variant for them. `custom.docker` replaces the
builtin `docker_context`, which hides itself for Docker Desktop's default
(`desktop-linux`) context; it shows when the directory has a Dockerfile / compose
file instead. The `git_*` modules are fixed
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

### yazi BIOS themes

Yazi ships three **hand-authored** retro-BIOS flavors — `mega-bios`, `laurel-bios`,
`firebird-bios` — under `configs/config/yazi/flavors/<name>.yazi/` (each just
`flavor.toml` + `tmtheme.xml` + LICENSE). The names are a deliberate **unaffiliated
homage** — evocative, not real firmware trademarks (`mega`←Megatrends-ish,
`laurel`←award wreath, `firebird`←phoenix). They have **no upstream repo**, so
`package.toml` carries **empty** `[plugin] deps` / `[flavor] deps` — never add
`[[flavor.deps]]` entries for them, and there is no `ya pkg` step. All three are
vendored in full (all kept, not just the active one — the installer lets the user
pick).

A flavor only sets **colors**. The BIOS *chrome* (grey/blue title bar showing the
cwd + a live clock, a frame around the panes, a centered key-legend, a POST tail
like `640K OK`) lives in `configs/config/yazi/init.lua`, which overrides `Root`
(banner row + framed panes + status row) and adds a right-side Status child. It
touches **no keymap** — the legend is a cosmetic label; the keys it names are
yazi's own bindings. Navigation/behavior is unchanged.

`init.lua` reads `theme.toml` at startup (`io.open`, guarded) to learn the active
flavor name and picks a matching chrome **preset** from its `PRESETS` table
(`tag`, `bar_bg/fg`, `frame` = `DOUBLE`/`PLAIN`, `legend`, `post`). So flipping
`[flavor] dark = "..."` swaps colors **and** chrome together; unknown/unreadable
names fall back to `mega-bios`.

The active theme is set in `configs/config/yazi/theme.toml`; the repo ships it in
its **canonical** default `dark = "mega-bios"`, and `apply_yazi_bios_theme` rewrites
it to the user's pick at install time. The whole `yazi/` dir (including `init.lua`
and all three flavors) is deployed as one unit by the Shell segment's
`for d in starship atuin bat yazi` loop — no separate deploy line.

**If you add/rename a BIOS flavor:** add its `flavors/<name>.yazi/` dir, add a
matching `PRESETS["<name>"]` entry in `init.lua`, and add the choice to
`apply_yazi_bios_theme`'s picker. **If you edit `init.lua`:** re-validate by
driving yazi in a pty (it renders even with a broken Lua init, so a syntax check
is not enough) — flip `theme.toml` through all three names and confirm each
preset's `tag` text renders with no Lua error.

### wezterm dotted background

`.wezterm.lua` sets `config.background` with two layers: the ink gradient (carrying
the 0.7 window transparency) and a repeated dot tile on top. `config.background`
makes wezterm **ignore** `window_background_gradient` / `window_background_opacity`,
so never re-add those — change the gradient/opacity on layer 1 instead.
`macos_window_background_blur` still applies.

The tile is not vendored: `dot_tile(DOT)` writes a tiny PNG (hand-rolled encoder,
stored deflate block + crc32/adler32) to `~/.cache/wezterm-dot-<spacing>-<size>-<alpha>.png`
on first load and reuses it after. Tune via the one line
`local DOT = { spacing = 6, size = 2, rgb = { 255, 255, 255 }, alpha = 12 }`
(physical pixels; retina 2px = 1pt; alpha 0–255) — new values just write a new
cache file. If the write fails, the dot layer is omitted and the gradient remains.
Validate edits with `wezterm --config-file <file> show-keys` (errors print to stderr).

## Key facts about the target setup

- Shell: zsh + oh-my-zsh, prompt via **starship** (not p10k).
- omz custom plugins cloned: `zsh-autosuggestions`, `fast-syntax-highlighting`.
- `.zshrc` sources `~/Documents/Tools/fzf-git.sh/fzf-git.sh` (installer clones it).
- Aliases redefine `ls`→eza, `cat`→bat, `cd`→zoxide `z`.
- `.zshrc` ends with atuin → starship → zoxide init; **zoxide must stay last** (it
  hooks precmd/chpwd and warns otherwise). No Homebrew command-not-found handler —
  removed on purpose, don't re-add.
- nvm is lazy-loaded (`nvm`/`node`/`npm`/`npx` stub functions), so `.zshrc` separately
  puts the **newest** `~/.nvm/versions/node/v*/bin` on PATH via a zsh glob
  (`v*(N/nOn[1])`) — that's what exposes global npm CLIs (hunk, pnpm). Never pin a
  node version path.
- Terminal: wezterm; font: **MesloLGS Nerd Font** (from `font-meslo-lg-nerd-font`);
  `font-jetbrains-mono-nerd-font` is installed alongside but not used by the config.
- bat uses a custom `tokyonight_night` theme → `bat cache --build` required post-deploy.
