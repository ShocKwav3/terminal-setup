
export UV_TOOLS="$HOME/.local/bin"
export BUN_INSTALL="$HOME/.bun/bin"
export PATH="$BUN_INSTALL/bin:$BUN_INSTALL:$UV_TOOLS:$PATH"

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Path to your starship config file
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"

ZSH_THEME="robbyrussell"

plugins=(
  git
  fzf
  zsh-autosuggestions
  fast-syntax-highlighting
  bgnotify
  safe-paste
  zsh-interactive-cd
)

source $ZSH/oh-my-zsh.sh

alias zshconfig="code ~/.zshrc"
alias starshipconfig="code ~/.config/starship/starship.toml"
alias weztermconfig="code ~/.wezterm.lua"
alias fastfetchconfig="code ~/.config/fastfetch/config.jsonc"
alias reloadshell="source ~/.zshrc"
alias ls="eza --color=always --long --git --icons=always --no-time --no-user --no-permissions --all --group-directories-first --total-size"
alias lsd="eza --color=always --tree --long --git --icons=always --no-user --no-permissions"
alias cd="z"
alias cat="bat"
alias syncTime="sudo sntp -sS time.apple.com"

unalias ls 2>/dev/null
ls() {
  if [[ "$1" == "-t" ]]; then
    shift
    eza --color=always --tree --long --git --icons=always \
        --no-user --no-permissions --all \
        --group-directories-first --total-size "$@"

  elif [[ "$1" == "-g" ]]; then
    shift
    eza --color=always --icons=always "$@"

  else
    eza --color=always --long --git --icons=always \
        --no-time --no-user --no-permissions --all \
        --group-directories-first --total-size "$@"
  fi
}


TIMEFMT=$'\n-----------------------\nCPU usage\t%P\nPeak memory: %M kb'

export NVM_DIR="$HOME/.nvm"
# Lazy-load nvm: defer the ~300ms nvm.sh init until node/npm/npx/nvm is first used
_load_nvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _load_nvm; nvm "$@"; }
node() { _load_nvm; node "$@"; }
npm()  { _load_nvm; npm "$@"; }
npx()  { _load_nvm; npx "$@"; }

# FZF stuff
source ~/Documents/Tools/fzf-git.sh/fzf-git.sh
export FZF_DEFAULT_OPTS=$FZF_DEFAULT_OPTS'
  --color=fg:-1,fg+:#d0d0d0,bg:-1,bg+:#262626
  --color=hl:#5f87af,hl+:#5fd7ff,info:#afaf87,marker:#87ff00
  --color=prompt:#d7005f,spinner:#af5fff,pointer:#af5fff,header:#87afaf
  --color=border:#262626,label:#aeaeae,query:#d9d9d9
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
  --marker=">" --pointer="◆" --separator="─" --scrollbar="│"
  --info="right"'

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
    export|unset) fzf --preview "eval 'echo \${}'"         "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    *)            fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}

# Yazi stuff
export EDITOR=code
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Custom stuff------------------------------------
# eval "$(fzf --zsh)" # Moved to plugin section
eval "$(atuin init zsh)"
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# if [ -z "$DISABLE_ZOXIDE" ]; then
    # eval "$(zoxide init --cmd cd zsh)"
# fi

#Command not found handler for Homebrew
HOMEBREW_COMMAND_NOT_FOUND_HANDLER="$(brew --repository)/Library/Homebrew/command-not-found/handler.sh"
if [ -f "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER" ]; then
  source "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER";
fi
