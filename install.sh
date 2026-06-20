#!/usr/bin/env bash
#
# install.sh — reproducible Mac terminal setup installer.
#
# Installs the tools, runtimes, fonts and shell plugins this setup needs
# (checking for each first and asking before installing), then deploys the
# config files from ./configs to their destinations. Safe to re-run: nothing
# already present is reinstalled, and configs are never overwritten silently.
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

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------
have()           { command -v "$1" >/dev/null 2>&1; }
brew_installed() { brew list --formula "$1" >/dev/null 2>&1; }
cask_installed() { brew list --cask "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Bootstrap
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
    if have brew; then ok "Installed."; else err "Homebrew install failed."; fi
  else
    warn "Skipped — brew formulae/casks below will be skipped too."
  fi
}

ensure_omz() {
  step "oh-my-zsh"
  if [ -d "$HOME/.oh-my-zsh" ]; then
    ok "Already installed."
    return
  fi
  summary "Zsh framework providing the plugin system this setup relies on."
  if confirm "Install oh-my-zsh?"; then
    RUNZSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    [ -d "$HOME/.oh-my-zsh" ] && ok "Installed." || err "oh-my-zsh install failed."
  else
    warn "Skipped — custom plugins below will be skipped too."
  fi
}

# ---------------------------------------------------------------------------
# Runtimes (curl installers, not brew)
# ---------------------------------------------------------------------------
ensure_runtimes() {
  step "Language runtimes"

  if [ -d "$HOME/.nvm" ]; then
    ok "nvm already installed."
  else
    summary "nvm — Node version manager (lazy-loaded in .zshrc)."
    if confirm "Install nvm?"; then
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
        && ok "nvm installed." || err "nvm install failed."
    else
      warn "Skipped nvm."
    fi
  fi

  if have bun || [ -d "$HOME/.bun" ]; then
    ok "bun already installed."
  else
    summary "bun — fast JS runtime/package manager (on PATH via .zshrc)."
    if confirm "Install bun?"; then
      curl -fsSL https://bun.sh/install | bash && ok "bun installed." || err "bun install failed."
    else
      warn "Skipped bun."
    fi
  fi

  if have uv || [ -x "$HOME/.local/bin/uv" ]; then
    ok "uv already installed."
  else
    summary "uv — Python package/tool manager (~/.local/bin on PATH)."
    if confirm "Install uv?"; then
      curl -LsSf https://astral.sh/uv/install.sh | sh && ok "uv installed." || err "uv install failed."
    else
      warn "Skipped uv."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Homebrew formulae (grouped prompts)
# ---------------------------------------------------------------------------
# ensure_formulae "summary line" formula [formula...]
ensure_formulae() {
  local summary_line="$1"; shift
  local pkgs missing p
  pkgs="$*"
  missing=""
  for p in "$@"; do
    brew_installed "$p" || missing="$missing $p"
  done
  missing="${missing# }"
  if [ -z "$missing" ]; then
    ok "Already installed:$( for p in "$@"; do printf ' %s' "$p"; done )"
    return
  fi
  summary "$summary_line"
  info "Will install:${missing:+ }$missing"
  if confirm "Install$( for p in $missing; do printf ' %s' "$p"; done )?"; then
    # shellcheck disable=SC2086
    brew install $missing && ok "Installed." || err "Some installs failed: $missing"
  else
    warn "Skipped: $missing"
  fi
}

ensure_casks() {
  local summary_line="$1"; shift
  local missing p
  missing=""
  for p in "$@"; do
    cask_installed "$p" || missing="$missing $p"
  done
  missing="${missing# }"
  if [ -z "$missing" ]; then
    ok "Already installed:$( for p in "$@"; do printf ' %s' "$p"; done )"
    return
  fi
  summary "$summary_line"
  info "Will install:${missing:+ }$missing"
  if confirm "Install$( for p in $missing; do printf ' %s' "$p"; done )?"; then
    # shellcheck disable=SC2086
    brew install --cask $missing && ok "Installed." || err "Some installs failed: $missing"
  else
    warn "Skipped: $missing"
  fi
}

install_formulae() {
  if ! have brew; then
    warn "Homebrew not available — skipping all brew formulae."
    return
  fi

  step "yazi (terminal file manager)"
  ensure_formulae \
    "yazi + preview deps: ffmpeg, poppler (PDF), resvg (SVG), imagemagick, 7zip. (Also uses fd/rg/fzf/zoxide/jq — prompted separately.)" \
    yazi ffmpeg-full poppler resvg imagemagick-full sevenzip

  step "Standalone CLI tools"
  ensure_formulae "atuin — magical shell history search (Ctrl-R)."                 atuin
  ensure_formulae "bat — cat clone with syntax highlighting (aliased to cat)."     bat
  ensure_formulae "eza — modern ls replacement (aliased to ls)."                   eza
  ensure_formulae "starship — cross-shell prompt."                                 starship
  ensure_formulae "git-delta — syntax-highlighting git pager (wired in .gitconfig)." git-delta
  ensure_formulae "fastfetch — system info display."                               fastfetch
  ensure_formulae "blueutil — Bluetooth control from the CLI."                     blueutil
  ensure_formulae "terminal-notifier — desktop notifications (omz bgnotify)."      terminal-notifier
  ensure_formulae "figlet — ASCII-art banners (used by this installer)."           figlet
  ensure_formulae "fzf — fuzzy finder (shell plugin, fzf-git, previews)."          fzf
  ensure_formulae "zoxide — smarter cd (aliased cd=z)."                            zoxide
  ensure_formulae "fd — fast file find (fzf default command, yazi)."               fd
  ensure_formulae "ripgrep — fast recursive grep."                                 ripgrep
  ensure_formulae "jq — command-line JSON processor."                              jq
}

install_casks() {
  if ! have brew; then
    warn "Homebrew not available — skipping casks."
    return
  fi
  step "Fonts"
  ensure_casks "Nerd Fonts for terminal glyphs/powerline (MesloLGS used by wezterm)." \
    font-meslo-lg-nerd-font font-symbols-only-nerd-font

  step "wezterm (GPU terminal emulator)"
  ensure_casks "wezterm — the terminal this config is built for (.wezterm.lua)." wezterm
}

# ---------------------------------------------------------------------------
# oh-my-zsh custom plugins
# ---------------------------------------------------------------------------
install_omz_plugins() {
  step "oh-my-zsh custom plugins"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    warn "oh-my-zsh not installed — skipping custom plugins."
    return
  fi
  local zcustom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local need_as=0 need_fsh=0
  [ -d "$zcustom/plugins/zsh-autosuggestions" ] || need_as=1
  [ -d "$zcustom/plugins/fast-syntax-highlighting" ] || need_fsh=1
  if [ "$need_as" -eq 0 ] && [ "$need_fsh" -eq 0 ]; then
    ok "Already installed: zsh-autosuggestions, fast-syntax-highlighting."
    return
  fi
  summary "zsh-autosuggestions (history-based suggestions) + fast-syntax-highlighting."
  if confirm "Clone missing custom plugins?"; then
    if [ "$need_as" -eq 1 ]; then
      git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        "$zcustom/plugins/zsh-autosuggestions" && ok "zsh-autosuggestions cloned." \
        || err "zsh-autosuggestions clone failed."
    fi
    if [ "$need_fsh" -eq 1 ]; then
      git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting \
        "$zcustom/plugins/fast-syntax-highlighting" && ok "fast-syntax-highlighting cloned." \
        || err "fast-syntax-highlighting clone failed."
    fi
  else
    warn "Skipped custom plugins."
  fi
}

# ---------------------------------------------------------------------------
# fzf-git.sh
# ---------------------------------------------------------------------------
install_fzf_git() {
  step "fzf-git.sh"
  local dest="$HOME/Documents/Tools/fzf-git.sh"
  if [ -d "$dest" ]; then
    ok "Already cloned."
    return
  fi
  summary "Key bindings for git objects in fzf (sourced by .zshrc)."
  if confirm "Clone fzf-git.sh to ~/Documents/Tools?"; then
    mkdir -p "$HOME/Documents/Tools"
    git clone --depth=1 https://github.com/junegunn/fzf-git.sh.git "$dest" \
      && ok "Cloned." || err "fzf-git.sh clone failed."
  else
    warn "Skipped fzf-git.sh."
  fi
}

# ---------------------------------------------------------------------------
# Config deployment
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

configure_git_identity() {
  step "Git identity"
  local cur_name cur_email name email
  cur_name="$(git config --global user.name 2>/dev/null || true)"
  cur_email="$(git config --global user.email 2>/dev/null || true)"
  if [ -n "$cur_name" ] || [ -n "$cur_email" ]; then
    info "Current: ${cur_name:-<unset>} <${cur_email:-unset}>"
    confirm "Keep existing git name/email?" && { ok "Kept."; return; }
  fi
  printf '%s' "  git user.name${cur_name:+ [$cur_name]}: "; read -r name
  printf '%s' "  git user.email${cur_email:+ [$cur_email]}: "; read -r email
  [ -z "$name" ] && name="$cur_name"
  [ -z "$email" ] && email="$cur_email"
  [ -n "$name" ]  && git config --global user.name  "$name"
  [ -n "$email" ] && git config --global user.email "$email"
  ok "Set git identity: ${name:-<unset>} <${email:-unset}>"
}

deploy_configs() {
  step "Deploy config files"
  summary "About to deploy into:"
  summary "  $DEST_HOME/.zshrc  $DEST_HOME/.wezterm.lua  $DEST_HOME/.gitconfig"
  summary "  $DEST_CONFIG/{atuin,bat,fastfetch,starship,yazi}"
  summary "Existing files are never overwritten without asking (keep/overwrite/diff)."
  if ! confirm "Deploy config files now?"; then
    warn "Skipped all config deployment."
    return
  fi

  deploy "$CONFIGS_DIR/home/.zshrc"     "$DEST_HOME/.zshrc"
  deploy "$CONFIGS_DIR/home/.wezterm.lua" "$DEST_HOME/.wezterm.lua"
  deploy "$CONFIGS_DIR/home/.gitconfig" "$DEST_HOME/.gitconfig"

  mkdir -p "$DEST_CONFIG"
  local d
  for d in atuin bat fastfetch starship yazi; do
    deploy "$CONFIGS_DIR/config/$d" "$DEST_CONFIG/$d"
  done

  # Git name/email injected separately (kept out of the repo's .gitconfig).
  if have git; then configure_git_identity; fi
}

# ---------------------------------------------------------------------------
# Post-install
# ---------------------------------------------------------------------------
post_install() {
  step "Post-install"
  if have bat; then
    bat cache --build >/dev/null 2>&1 && ok "Rebuilt bat theme cache (tokyonight)." \
      || warn "bat cache --build failed (run it manually after install)."
  fi
  cat <<EOF

${C_GREEN}${C_BOLD}Done.${C_RESET} Next steps:
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

  ensure_xcode_clt
  ensure_homebrew
  ensure_omz
  ensure_runtimes
  install_formulae
  install_casks
  install_omz_plugins
  install_fzf_git
  deploy_configs
  post_install
}

main "$@"
