# terminal-setup

One-shot macOS terminal setup. Run one script on a fresh Mac and get the whole
environment back — tools, runtimes, fonts, shell plugins, and all config files —
without redoing it by hand.

## Screenshots

| | |
|---|---|
| ![starship prompt + wezterm tabs](images/sample1.png) | ![starship git status](images/sample3.png) |
| **starship** prompt + wezterm tab bar | dirty-tree git status in the prompt |
| ![yazi file manager](images/sample2.png) | ![fzf + bat preview](images/sample4.png) |
| **yazi** file manager (preview pane) | **fzf** finder with **bat** preview |
| ![interactive cd](images/sample5.png) | ![fzf-git log browser](images/sample6.png) |
| interactive `cd` completion | **fzf-git** commit browser |
| ![bat syntax highlighting](images/sample7.png) | ![eza listing](images/sample8.png) |
| **bat** syntax highlighting (`cat`) | **eza** listing (`ls`) |
| ![atuin history search](images/sample9.png) | ![starship in a node project](images/sample10.png) |
| **atuin** history search (Ctrl-R) | **starship** in a Node/pnpm project |

## Usage

```bash
git clone <this-repo> terminal-setup     # or copy the folder over
cd terminal-setup
./install.sh
```

The installer is **interactive and safe to re-run**:

- Checks for each tool first; skips anything already installed.
- Prints a one-line summary of what a tool is + why before asking.
- Prompts before every install (Enter = yes).
- Never overwrites a config silently — see [Config deployment](#config-deployment).

After it finishes: restart the terminal (or `source ~/.zshrc`) and select
**MesloLGS Nerd Font** in your terminal app.

## What it installs

**Bootstrap** (in order): Xcode Command Line Tools → Homebrew → oh-my-zsh.

**Runtimes** (curl installers): `nvm`, `bun`, `uv`.

**Homebrew formulae:**

| Tool | Purpose |
|------|---------|
| yazi (+ ffmpeg, poppler, resvg, imagemagick, sevenzip) | terminal file manager + file previews |
| atuin | shell history search (Ctrl-R) |
| bat | `cat` with syntax highlighting (aliased to `cat`) |
| eza | modern `ls` (aliased to `ls`) |
| starship | shell prompt |
| git-delta | git diff pager (wired in `.gitconfig`) |
| fastfetch | system info display |
| blueutil | Bluetooth control from the CLI |
| terminal-notifier | desktop notifications (omz `bgnotify`) |
| figlet | ASCII banners (used by the installer) |
| fzf | fuzzy finder (shell plugin, fzf-git, previews) |
| zoxide | smarter `cd` (aliased `cd`→`z`) |
| fd | fast file find |
| ripgrep | fast recursive grep |
| jq | JSON processor |

**Casks:** `font-meslo-lg-nerd-font`, `font-symbols-only-nerd-font`, `wezterm`.

**oh-my-zsh custom plugins** (git clone): `zsh-autosuggestions`,
`fast-syntax-highlighting`.

**Other:** clones `fzf-git.sh` to `~/Documents/Tools/` (sourced by `.zshrc`).

## Config deployment

Configs live in `configs/` and are copied to their destinations:

```
configs/home/   → $HOME            (.zshrc, .wezterm.lua, .gitconfig)
configs/config/ → $HOME/.config    (atuin, bat, fastfetch, starship, yazi)
```

Deployment is gated by one confirm. For each file that already exists you choose:

- **k** — keep the existing file
- **o** — overwrite (the old file is backed up to `<file>.bak.<timestamp>` first)
- **d** — show a diff, then ask again

**Git identity:** `configs/home/.gitconfig` ships **without** name/email. The
installer prompts you for them and sets them via `git config --global` (so they're
never committed to the repo).

## Notes & gotchas

- **macOS only**, Apple Silicon assumed (Homebrew at `/opt/homebrew`).
- **bat theme:** uses a custom `tokyonight_night` theme; the installer runs
  `bat cache --build` automatically at the end.
- **yazi theme:** the active flavor is `bluloco-dark` (set in
  `configs/config/yazi/theme.toml`). Flavors are vendored, so no extra download.
- **nvm / bun / uv** are lazy-loaded in `.zshrc` — first use initializes them.
- **Not included:** Claude Code / AI-tool configs (`opencode`, `ccstatusline`) are
  intentionally left out of scope.
- **Backups:** any overwritten config leaves a timestamped `.bak` next to it; clean
  those up yourself once you're happy.

## Updating the repo from your machine

Edit files under `configs/` directly (not `~`). Keep the tree clean — no
`.DS_Store`, `*.bak`, `.git` dirs, or theme `preview.png`/`README.md`. For yazi,
keep only the active flavor and update `theme.toml` + `package.toml` to match.

## Repo layout

```
install.sh    # the entire installer (single file, bash 3.2-safe)
configs/      # config files deployed to $HOME and $HOME/.config
images/       # screenshots used in this README
CLAUDE.md     # guidance for AI agents working in this repo
README.md     # this file
```
