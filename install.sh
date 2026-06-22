#!/usr/bin/env bash
#
# install.sh — reproducible Mac terminal setup installer.
#
# Bootstraps a fresh Mac (Xcode CLT → Homebrew), then walks four segments, each
# asking before it acts:
#   1. Terminal     — wezterm + the tools its config hard-depends on
#   2. Shell        — oh-my-zsh + everything .zshrc integrates
#   3. Git          — identity / optional SSH key + git-delta (via git config)
#   4. Claude Code  — CLI + plugins + node shim + settings.json
# Config-bearing shell/terminal tools are installed *and* configured together
# (the configs assume the tools), so those segments are all-or-nothing. Safe to
# re-run: nothing already present is reinstalled, configs are never overwritten
# silently. Ends with a summary of what was installed / configured / skipped.
#
# Written bash 3.2-safe (macOS default /bin/bash). No associative arrays.

# Continue on errors from individual installs so one failure doesn't abort the
# whole run; we report and move on. Fail fast only on unset variables.
set -u

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# Destination home — overridable for safe testing (INSTALL_HOME=/tmp/x ./install.sh).
DEST_HOME="${INSTALL_HOME:-$HOME}"
DEST_CONFIG="$DEST_HOME/.config"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_BOLD=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

info()  { printf '%s\n' "${C_BLUE}•${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}✓${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}!${C_RESET} $*"; }
err()   { printf '%s\n' "${C_RED}✗${C_RESET} $*" >&2; }

step() {
  printf '\n%s\n' "${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"
}

summary() {
  # Indented descriptive lines printed before a prompt.
  printf '%s\n' "${C_DIM}    $*${C_RESET}"
}

banner() {
  printf '\n'
  if command -v figlet >/dev/null 2>&1; then
    figlet -w 100 "Mac Setup" 2>/dev/null || printf '%s\n' "${C_BOLD}Mac Setup${C_RESET}"
  else
    printf '%s\n' "${C_BOLD}========== Mac Setup ==========${C_RESET}"
  fi
  printf '%s\n\n' "${C_DIM}terminal + tools + configs${C_RESET}"
}

# confirm "question"  -> returns 0 for yes, 1 for no. Default: yes (just Enter).
confirm() {
  local reply
  printf '%s' "${C_BOLD}?${C_RESET} $1 ${C_DIM}[Y/n]${C_RESET} "
  read -r reply
  case "$reply" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# prompt_choice "question" <default_val> <other_val>
# Two-way picker. Enter / 1 picks the default; 2 picks the other.
# Result is left in the global REPLY_CHOICE.
prompt_choice() {
  local reply
  printf '%s' "${C_BOLD}?${C_RESET} $1 ${C_DIM}[1] $2 (default) / [2] $3${C_RESET} "
  read -r reply
  case "$reply" in
    2) REPLY_CHOICE="$3" ;;
    *) REPLY_CHOICE="$2" ;;
  esac
}

# ---------------------------------------------------------------------------
# Run summary accumulators (indexed arrays — bash 3.2 safe)
# ---------------------------------------------------------------------------
REC_INSTALLED=()
REC_CONFIGURED=()
REC_SKIPPED=()

# record <installed|configured|skipped> <item>
record() {
  case "$1" in
    installed)  REC_INSTALLED+=("$2") ;;
    configured) REC_CONFIGURED+=("$2") ;;
    skipped)    REC_SKIPPED+=("$2") ;;
  esac
}

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------
have()           { command -v "$1" >/dev/null 2>&1; }
brew_installed() { brew list --formula "$1" >/dev/null 2>&1; }
cask_installed() { brew list --cask "$1" >/dev/null 2>&1; }

# brew_formulae <pkg...> — install any missing formulae in one go, record them.
brew_formulae() {
  if ! have brew; then warn "Homebrew unavailable — skipping:$(printf ' %s' "$@")"; return; fi
  local missing="" p
  for p in "$@"; do brew_installed "$p" || missing="$missing $p"; done
  missing="${missing# }"
  if [ -z "$missing" ]; then ok "Already installed:$(printf ' %s' "$@")"; return; fi
  info "Installing:$( for p in $missing; do printf ' %s' "$p"; done )"
  # shellcheck disable=SC2086
  if brew install $missing; then
    for p in $missing; do record installed "$p"; done
    ok "Installed:$( for p in $missing; do printf ' %s' "$p"; done )"
  else
    err "Some installs failed:$missing"
  fi
}

# brew_casks <pkg...> — same, for casks.
brew_casks() {
  if ! have brew; then warn "Homebrew unavailable — skipping:$(printf ' %s' "$@")"; return; fi
  local missing="" p
  for p in "$@"; do cask_installed "$p" || missing="$missing $p"; done
  missing="${missing# }"
  if [ -z "$missing" ]; then ok "Already installed:$(printf ' %s' "$@")"; return; fi
  info "Installing:$( for p in $missing; do printf ' %s' "$p"; done )"
  # shellcheck disable=SC2086
  if brew install --cask $missing; then
    for p in $missing; do record installed "$p"; done
    ok "Installed:$( for p in $missing; do printf ' %s' "$p"; done )"
  else
    err "Some installs failed:$missing"
  fi
}

# ---------------------------------------------------------------------------
# Bootstrap (prerequisites — run before the segments)
# ---------------------------------------------------------------------------
ensure_xcode_clt() {
  step "Xcode Command Line Tools"
  if xcode-select -p >/dev/null 2>&1; then
    ok "Already installed."
    return
  fi
  summary "Required by Homebrew and git. Triggers Apple's GUI installer."
  if confirm "Install Xcode Command Line Tools?"; then
    xcode-select --install >/dev/null 2>&1
    warn "A GUI installer was launched. Finish it, then press Enter to continue."
    read -r _
    if ! xcode-select -p >/dev/null 2>&1; then
      err "Command Line Tools still not detected. Re-run this script once they finish installing."
      exit 1
    fi
    ok "Installed."
    record installed "Xcode Command Line Tools"
  else
    warn "Skipped — Homebrew install will likely fail without it."
  fi
}

ensure_homebrew() {
  step "Homebrew"
  if have brew; then
    ok "Already installed ($(brew --version | head -n1))."
    return
  fi
  summary "Package manager used to install most CLI tools and fonts."
  if confirm "Install Homebrew?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      && [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    if have brew; then ok "Installed."; record installed "Homebrew"; else err "Homebrew install failed."; fi
  else
    warn "Skipped — brew formulae/casks below will be skipped too."
  fi
}

# figlet powers the start/end banners — install quietly so they render.
ensure_figlet() {
  have figlet && return
  have brew || return
  brew install figlet >/dev/null 2>&1 && record installed "figlet" || true
}

# ---------------------------------------------------------------------------
# Runtimes (curl installers, not brew) — called within the Shell segment
# ---------------------------------------------------------------------------
ensure_nvm() {
  if [ -d "$HOME/.nvm" ]; then
    ok "nvm already installed."
    return
  fi
  info "Installing nvm…"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && { ok "nvm installed."; record installed "nvm"; } || err "nvm install failed."
}

# ensure_node — a node version must actually exist (nvm only provides the manager).
# Needed by the node shim and by Claude plugin hooks. Installs the latest LTS.
ensure_node() {
  ensure_nvm
  local d="$HOME/.nvm/versions/node"
  if [ -d "$d" ] && [ -n "$(ls "$d" 2>/dev/null)" ]; then
    ok "node already installed (nvm)."
  elif [ -s "$HOME/.nvm/nvm.sh" ]; then
    info "Installing latest LTS node via nvm…"
    # shellcheck disable=SC1091
    if ( export NVM_DIR="$HOME/.nvm"; \. "$HOME/.nvm/nvm.sh"; nvm install --lts ); then
      ok "node (LTS) installed."; record installed "node (LTS)"
    else
      err "node install failed."
    fi
  else
    warn "nvm not present — skipping node install."
  fi
  install_node_shim
}

# install_node_shim — make `node` resolvable for non-interactive shells. Claude
# Code runs hooks via /bin/sh, which never sources ~/.zshrc, so nvm's lazy node()
# function is absent and bare `node` fails. This shim (on ~/.local/bin, already on
# PATH) resolves the newest installed nvm node at call time — survives nvm upgrades.
# Interactive zsh is unaffected: the node() function in .zshrc shadows it.
install_node_shim() {
  local shim="$HOME/.local/bin/node"
  mkdir -p "$HOME/.local/bin"
  cat > "$shim" <<'SH'
#!/bin/sh
# nvm node shim for non-interactive shells (see install.sh: install_node_shim).
d="$HOME/.nvm/versions/node"
v="$(ls "$d" 2>/dev/null | sort -V | tail -1)"
[ -n "$v" ] && exec "$d/$v/bin/node" "$@"
echo "node: no nvm node found under $d" >&2
exit 127
SH
  chmod +x "$shim"
  ok "node shim ready → ~/.local/bin/node"
  # ensure_node may run in both the Shell and Claude segments — record once.
  if [ "${_SHIM_RECORDED:-0}" != 1 ]; then
    record configured "node shim (~/.local/bin/node)"
    _SHIM_RECORDED=1
  fi
}

ensure_bun() {
  if have bun || [ -d "$HOME/.bun" ]; then
    ok "bun already installed."
    return
  fi
  info "Installing bun…"
  curl -fsSL https://bun.sh/install | bash \
    && { ok "bun installed."; record installed "bun"; } || err "bun install failed."
}

ensure_uv() {
  if have uv || [ -x "$HOME/.local/bin/uv" ]; then
    ok "uv already installed."
    return
  fi
  info "Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh \
    && { ok "uv installed."; record installed "uv"; } || err "uv install failed."
}

# ---------------------------------------------------------------------------
# oh-my-zsh + shell plugins (called within the Shell segment)
# ---------------------------------------------------------------------------
ensure_omz() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    ok "oh-my-zsh already installed."
    return
  fi
  info "Installing oh-my-zsh…"
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  if [ -d "$HOME/.oh-my-zsh" ]; then ok "Installed."; record installed "oh-my-zsh"; else err "oh-my-zsh install failed."; fi
}

install_omz_plugins() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    warn "oh-my-zsh not installed — skipping custom plugins."
    return
  fi
  local zcustom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [ ! -d "$zcustom/plugins/zsh-autosuggestions" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
      "$zcustom/plugins/zsh-autosuggestions" \
      && { ok "zsh-autosuggestions cloned."; record installed "zsh-autosuggestions"; } \
      || err "zsh-autosuggestions clone failed."
  else
    ok "zsh-autosuggestions already present."
  fi
  if [ ! -d "$zcustom/plugins/fast-syntax-highlighting" ]; then
    git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting \
      "$zcustom/plugins/fast-syntax-highlighting" \
      && { ok "fast-syntax-highlighting cloned."; record installed "fast-syntax-highlighting"; } \
      || err "fast-syntax-highlighting clone failed."
  else
    ok "fast-syntax-highlighting already present."
  fi
}

install_fzf_git() {
  local dest="$HOME/Documents/Tools/fzf-git.sh"
  if [ -d "$dest" ]; then
    ok "fzf-git.sh already cloned."
    return
  fi
  mkdir -p "$HOME/Documents/Tools"
  git clone --depth=1 https://github.com/junegunn/fzf-git.sh.git "$dest" \
    && { ok "fzf-git.sh cloned."; record installed "fzf-git.sh"; } || err "fzf-git.sh clone failed."
}

# ---------------------------------------------------------------------------
# Config deployment helpers
# ---------------------------------------------------------------------------
show_diff() {
  # show_diff <dest> <src>
  local dest="$1" src="$2"
  if [ -d "$src" ] || [ -d "$dest" ]; then
    diff -ru "$dest" "$src" | ${PAGER:-less -R} 2>/dev/null || diff -ru "$dest" "$src" || true
  elif have delta; then
    delta "$dest" "$src" || true
  else
    diff -u "$dest" "$src" || true
  fi
}

# deploy <src> <dest> — copy src to dest with conflict handling.
deploy() {
  local src="$1" dest="$2" reply
  if [ ! -e "$src" ]; then
    warn "Missing in repo, skipping: $src"
    return
  fi
  if [ ! -e "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -R "$src" "$dest" && ok "Installed $dest" || err "Failed to copy $dest"
    return
  fi
  while true; do
    printf '%s' "${C_YELLOW}?${C_RESET} ${C_BOLD}$(basename "$dest")${C_RESET} exists. ${C_DIM}[k]eep / [o]verwrite / [d]iff${C_RESET} "
    read -r reply
    case "$reply" in
      [oO])
        local bak="$dest.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$bak" && info "Backed up to $bak"
        cp -R "$src" "$dest" && ok "Overwrote $dest" || err "Failed to copy $dest"
        return ;;
      [dD])
        show_diff "$dest" "$src" ;;
      *)
        info "Kept existing $dest"; return ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Segment 1 — Terminal (wezterm + its hard dependencies)
# ---------------------------------------------------------------------------
segment_terminal() {
  step "Terminal — wezterm"
  summary "Installs: wezterm, MesloLGS + symbols Nerd Fonts, blueutil (wezterm BT status),"
  summary "  fastfetch (wezterm runs it on startup)."
  summary "Configures: ~/.wezterm.lua, ~/.config/fastfetch"
  summary "The wezterm config depends on these, so they install + configure together."
  if ! confirm "Set up the terminal (wezterm)?"; then
    warn "Skipped terminal setup."; record skipped "Terminal (wezterm)"; return
  fi
  brew_casks wezterm font-meslo-lg-nerd-font font-symbols-only-nerd-font
  brew_formulae blueutil fastfetch
  deploy "$CONFIGS_DIR/home/.wezterm.lua" "$DEST_HOME/.wezterm.lua"; record configured ".wezterm.lua"
  mkdir -p "$DEST_CONFIG"
  deploy "$CONFIGS_DIR/config/fastfetch" "$DEST_CONFIG/fastfetch"; record configured "fastfetch"
}

# ---------------------------------------------------------------------------
# Segment 2 — Shell (oh-my-zsh + everything .zshrc integrates)
# ---------------------------------------------------------------------------
segment_shell() {
  step "Shell — zsh + oh-my-zsh"
  summary "Installs: oh-my-zsh + plugins (zsh-autosuggestions, fast-syntax-highlighting),"
  summary "  starship, atuin, bat, eza, zoxide, fzf, fd, ripgrep, jq,"
  summary "  yazi (+ ffmpeg/poppler/resvg/imagemagick/sevenzip previews), terminal-notifier,"
  summary "  nvm + node, bun, uv; clones fzf-git.sh."
  summary "Configures: ~/.zshrc, ~/.config/{starship,atuin,bat,yazi}, node shim, bat theme, starship prompt style."
  summary "Note: fd/ripgrep/jq power fzf & yazi — part of the shell, not optional here."
  if ! confirm "Set up the shell (zsh + oh-my-zsh)?"; then
    warn "Skipped shell setup."; record skipped "Shell (zsh/omz)"; return
  fi

  # --- installs ---
  ensure_omz
  brew_formulae starship atuin bat eza zoxide fzf fd ripgrep jq \
    yazi ffmpeg-full poppler resvg imagemagick-full sevenzip terminal-notifier
  ensure_node      # nvm + node + shim
  ensure_bun
  ensure_uv
  install_omz_plugins
  install_fzf_git

  # --- configs ---
  deploy "$CONFIGS_DIR/home/.zshrc" "$DEST_HOME/.zshrc"; record configured ".zshrc"
  mkdir -p "$DEST_CONFIG"
  local d
  for d in starship atuin bat yazi; do
    deploy "$CONFIGS_DIR/config/$d" "$DEST_CONFIG/$d"; record configured "$d"
  done
  apply_starship_variants
  if have bat; then
    bat cache --build >/dev/null 2>&1 && ok "Rebuilt bat theme cache (tokyonight)." \
      || warn "bat cache --build failed (run it manually after install)."
  fi
}

# ---------------------------------------------------------------------------
# Starship prompt variants
# ---------------------------------------------------------------------------
# The deployed starship.toml ships in its canonical form: colorful + icon-only.
# Each module carries its alternates as commented blocks marked v1/v2/verbose/v4.
# This prompts for two independent axes and flips the deployed copy to match by
# uncommenting the chosen block per module and commenting the others. The repo
# copy is always the baseline, so the transform is deterministic / idempotent.
#
#   color  : colorful (brand colors)  | lesscolor (grey + dim white)
#   info   : icon (icon only)         | verbose (icon + tool version)
#
#   colorful + icon    -> v1     lesscolor + icon    -> v2
#   colorful + verbose -> verbose lesscolor + verbose -> v4
#
# Color-only modules (no version concept) carry just v1/v2; for those the info
# axis falls back to the matching icon variant.
apply_starship_variants() {
  local f="$DEST_CONFIG/starship/starship.toml"
  local repo="$CONFIGS_DIR/config/starship/starship.toml"
  [ -f "$f" ] || return
  # Only transform the file we shipped this run. A kept or customized
  # starship.toml may be missing some variant blocks (e.g. an older copy with no
  # v4) — rewriting it could leave a module with no active format — and editing it
  # would silently mutate a file the user chose to keep. So require a byte-for-byte
  # match with the repo baseline before touching it.
  if ! diff -q "$f" "$repo" >/dev/null 2>&1; then
    info "starship.toml differs from the repo copy (kept/custom) — leaving prompt style as-is."
    return
  fi

  step "Starship prompt style"
  summary "Two independent choices. The defaults reproduce the shipped look."
  local color info_mode
  prompt_choice "Tool versions in the prompt?" "icon" "verbose"; info_mode="$REPLY_CHOICE"
  prompt_choice "Color scheme?"                "colorful" "lesscolor"; color="$REPLY_CHOICE"

  if [ "$color" = "colorful" ] && [ "$info_mode" = "icon" ]; then
    ok "Keeping default starship style (colorful + icon-only)."
    return
  fi

  local tmp; tmp="$(mktemp)"
  if awk -v COLOR="$color" -v INFO="$info_mode" '
    function marker_name(l) {
      if (l ~ /^# v1 \(orig colorful/)          return "v1"
      if (l ~ /^# v2 \(less-color icon-only/)   return "v2"
      if (l ~ /^# --- verbose \(version\) below/) return "verbose"
      if (l ~ /^# v4 \(less-color verbose/)     return "v4"
      return ""
    }
    function uncomment(l)  { sub(/^# /, "", l); return l }
    function commentize(l) { if (l !~ /^#/) l = "# " l; return l }
    function flush(   i, line, vt, hasV, target, cmd_on, val) {
      if (n == 0) return
      hasV = 0
      for (i = 1; i <= n; i++) if (buf[i] ~ /^# --- verbose \(version\) below/) hasV = 1
      if      (COLOR == "colorful"  && INFO == "icon")    { target = "v1"; cmd_on = 0 }
      else if (COLOR == "lesscolor" && INFO == "icon")    { target = "v2"; cmd_on = 0 }
      else if (COLOR == "colorful"  && INFO == "verbose") { if (hasV) { target = "verbose"; cmd_on = 1 } else { target = "v1"; cmd_on = 0 } }
      else                                                { if (hasV) { target = "v4";      cmd_on = 1 } else { target = "v2"; cmd_on = 0 } }
      i = 1
      while (i <= n) {
        line = buf[i]
        vt = marker_name(line)
        if (vt != "") {
          print line; i++                       # marker line is left untouched
          if (i <= n) {
            val = buf[i]
            if (val ~ /^#?[ ]*format[ ]*=[ ]*"""/) {   # multiline value
              if (vt == target) print uncomment(val); else print commentize(val)
              i++
              while (i <= n) {
                val = buf[i]
                if (vt == target) print uncomment(val); else print commentize(val)
                i++
                if (val ~ /^#?[ ]*"""[ ]*$/) break
              }
            } else {                                   # single-line value
              if (vt == target) print uncomment(val); else print commentize(val)
              i++
            }
          }
          continue
        }
        if (line ~ /^#?[ ]*command[ ]*=/) {
          if (cmd_on) print uncomment(line); else print commentize(line)
          i++; continue
        }
        print line; i++
      }
      n = 0
    }
    # Flush on a real TOML table header only. Multiline format *values* begin
    # with "[" too (e.g. [](fg:...)), so match a bare [name] line, nothing else.
    /^\[[^]]+\][ \t]*$/ { flush() }
    { buf[++n] = $0 }
    END { flush() }
  ' "$f" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$f"
    ok "Applied starship style: $color + $info_mode."
  else
    rm -f "$tmp"
    err "Failed to apply starship variants — left starship.toml unchanged."
  fi
}

# ---------------------------------------------------------------------------
# Segment 3 — Git (+ git-delta)
# ---------------------------------------------------------------------------
# Identity, the optional SSH key, and git-delta are all applied via
# `git config --global` / ssh-keygen rather than copying a .gitconfig, so the new
# machine's own git policy is preserved — we only add our keys.
segment_git() {
  step "Git"
  if have git; then
    ok "git already installed ($(git --version 2>/dev/null))."
  else
    summary "git — version control (and the base git-delta plugs into)."
    if confirm "Install git?"; then
      brew_formulae git
    else
      warn "Skipped git — also skipping git config and git-delta."
      record skipped "Git"
      return
    fi
  fi
  configure_git
  configure_git_delta
}

configure_git() {
  if ! confirm "Configure git (name/email, optional SSH key)?"; then
    record skipped "git config"
    return
  fi
  local name email
  printf '%s' "  git user.name: ";  read -r name
  printf '%s' "  git user.email: "; read -r email
  [ -n "$name" ]  && git config --global user.name  "$name"
  [ -n "$email" ] && git config --global user.email "$email"
  git config --global diff.colorMoved default
  ok "Set git identity: ${name:-<unset>} <${email:-unset}> (+ diff.colorMoved=default)"
  record configured "git identity"

  if confirm "Generate an SSH key (ed25519)?"; then
    local ctx pass keyfile
    printf '%s' "  context (e.g. personal, work): "; read -r ctx
    [ -z "$ctx" ] && ctx="personal"
    printf '%s' "  passphrase (empty for none): "; read -rs pass; printf '\n'
    keyfile="$HOME/.ssh/id_ed25519_${ctx}"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    if [ -f "$keyfile" ]; then
      warn "Key already exists: $keyfile — skipping generation."
    elif ssh-keygen -t ed25519 -C "${email:-$ctx}" -f "$keyfile" -N "$pass"; then
      ok "SSH key created: $keyfile"
      record configured "ssh key ($ctx)"
      info "Public key (add to GitHub → https://github.com/settings/keys):"
      cat "$keyfile.pub"
    else
      err "ssh-keygen failed."
    fi
  fi
}

configure_git_delta() {
  step "git-delta"
  if ! have git; then
    warn "git not available — skipping git-delta."
    return
  fi
  if brew_installed git-delta || have delta; then
    ok "git-delta already installed."
  else
    summary "git-delta — syntax-highlighting diff pager for git."
    if ! confirm "Install git-delta?"; then
      warn "Skipped git-delta."; record skipped "git-delta"; return
    fi
    brew_formulae git-delta
  fi
  # Installed delta is useless unconfigured, so wire it up immediately.
  git config --global core.pager delta
  git config --global interactive.diffFilter 'delta --color-only'
  git config --global delta.navigate true
  git config --global merge.conflictStyle zdiff3
  ok "Configured git-delta (pager, diffFilter, navigate, zdiff3)."
  record configured "git-delta"
}

# ---------------------------------------------------------------------------
# Segment 4 — Claude Code
# ---------------------------------------------------------------------------
segment_claude() {
  step "Claude Code"
  if have claude; then
    ok "Claude Code already installed ($(claude --version 2>/dev/null))."
  else
    summary "Claude Code — Anthropic's agentic coding CLI (native installer)."
    if confirm "Install Claude Code?"; then
      info "Installing Claude Code…"
      curl -fsSL https://claude.ai/install.sh | bash \
        && { ok "Claude Code installed."; record installed "Claude Code"; } \
        || err "Claude Code install failed."
    else
      warn "Skipped Claude Code."; record skipped "Claude Code"; return
    fi
  fi

  summary "Configure will: ensure node + shim, add marketplaces (caveman, plannotator),"
  summary "  install plugins (superpowers, typescript-lsp, caveman, plannotator),"
  summary "  deploy ~/.claude/settings.json."
  if ! confirm "Configure Claude Code now?"; then
    record skipped "Claude config"
    return
  fi

  # Plugin hooks (e.g. caveman) run via /bin/sh and call bare `node`; ensure node
  # + the shim exist so they resolve. (Also done in the Shell segment; idempotent.)
  ensure_node

  if have claude; then
    claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null \
      && ok "marketplace: claude-plugins-official" || warn "marketplace claude-plugins-official: add failed or already present."
    claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null \
      && ok "marketplace: caveman" || warn "marketplace caveman: add failed or already present."
    claude plugin marketplace add backnotprop/plannotator 2>/dev/null \
      && ok "marketplace: plannotator" || warn "marketplace plannotator: add failed or already present."
    local p
    for p in superpowers@claude-plugins-official typescript-lsp@claude-plugins-official \
             caveman@caveman plannotator@plannotator; do
      claude plugin install "$p" 2>/dev/null && ok "plugin: $p" \
        || warn "plugin $p: install failed or already present."
    done
    record configured "claude plugins"
  else
    warn "claude CLI not available — skipping plugin install."
  fi

  mkdir -p "$DEST_HOME/.claude"
  deploy "$CONFIGS_DIR/claude/settings.json" "$DEST_HOME/.claude/settings.json"
  record configured "claude settings.json"
}

# ---------------------------------------------------------------------------
# Final summary + banner
# ---------------------------------------------------------------------------
final_summary() {
  step "Summary"
  printf '%s\n' "${C_BOLD}Installed:${C_RESET}"
  if [ "${#REC_INSTALLED[@]}" -gt 0 ]; then printf '  • %s\n' "${REC_INSTALLED[@]}"; else printf '%s\n' "${C_DIM}    (nothing new)${C_RESET}"; fi
  printf '%s\n' "${C_BOLD}Configured:${C_RESET}"
  if [ "${#REC_CONFIGURED[@]}" -gt 0 ]; then printf '  • %s\n' "${REC_CONFIGURED[@]}"; else printf '%s\n' "${C_DIM}    (nothing)${C_RESET}"; fi
  if [ "${#REC_SKIPPED[@]}" -gt 0 ]; then
    printf '%s\n' "${C_BOLD}Skipped:${C_RESET}"; printf '  • %s\n' "${REC_SKIPPED[@]}"
  fi

  printf '\n'
  if command -v figlet >/dev/null 2>&1; then
    figlet -w 100 "All Done" 2>/dev/null || printf '%s\n' "${C_BOLD}All Done${C_RESET}"
  else
    printf '%s\n' "${C_BOLD}========== All Done ==========${C_RESET}"
  fi
  cat <<EOF
${C_GREEN}${C_BOLD}Setup complete.${C_RESET} Next steps:
  • Restart your terminal, or run: ${C_BOLD}source ~/.zshrc${C_RESET}
  • In your terminal settings, select the ${C_BOLD}MesloLGS Nerd Font${C_RESET}.
  • nvm / bun / uv are lazy-loaded; first use initializes them.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ "$(uname)" != "Darwin" ]; then
    err "This installer targets macOS only."
    exit 1
  fi
  banner

  # Bootstrap (prerequisites)
  ensure_xcode_clt
  ensure_homebrew
  ensure_figlet

  # Segments
  segment_terminal
  segment_shell
  segment_git
  segment_claude

  final_summary
}

main "$@"
