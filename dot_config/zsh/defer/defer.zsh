# zsh keybind
## see docs https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-binding-keys
bindkey -r '^J' # Ctrl-j
# git wrapper
function git () {
  local ispush
  ispush=0
  local isforce
  isforce=0
  for arg in "$@"; do
    if [[ "$arg" == "push" ]]; then
      ispush=1
    fi
    if [ "$ispush" -eq 1 ]; then
      if [[ "$arg" == '--force' ]] || [[ "$arg" =~ ^\-[^\-]*f.*$ ]]; then
        isforce=1
      fi
    fi
    if [ $isforce -eq 1 ]; then
      >&2 echo "Please use '--force-with-lease' instead of '--force'."
      return 1
    fi
  done
  command git "$@"
}
# mise
eval "$(mise activate zsh)"
eval "$(mise completion zsh)"

# Rust
source $XDG_DATA_HOME/cargo/env

# direnv
eval "$(direnv hook zsh)"

# fzf
function fzf-select-history() {
  BUFFER=$(history -n -r 1 | fzf --query "$LBUFFER")
  CURSOR=$#BUFFER
  zle reset-prompt
}
zle -N fzf-select-history
bindkey '^r' fzf-select-history

fzf_cd() {
  local search_dir=${1:-$HOME}
  local target_dir=$(fd --type directory \
    --exclude .git \
    --hidden \
    --no-ignore \
    . $search_dir | fzf --prompt='CHANGE DIRECTORY > ') &&
    if [ -n "$target_dir" ]; then
      echo "cd $target_dir"
      cd "$target_dir"
    fi
}
zle -N fzf_cd
bindkey '^o' fzf_cd

export FZF_DEFAULT_OPTS='--reverse --border --ansi --bind="ctrl-d:print-query,ctrl-p:replace-query" --inline-info --height 80%'
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'


# -----------------------------------------------------------------------------
# directory
# -----------------------------------------------------------------------------

# fzf --preview command for file and directory
if type bat >/dev/null 2>&1; then
    FZF_PREVIEW_CMD='bat --color=always --plain --line-range :$FZF_PREVIEW_LINES {}'
elif type pygmentize >/dev/null 2>&1; then
    FZF_PREVIEW_CMD='head -n $FZF_PREVIEW_LINES {} | pygmentize -g'
else
    FZF_PREVIEW_CMD='head -n $FZF_PREVIEW_LINES {}'
fi

# zdd - cd to selected directory
zdd() {
  local dir
  dir="$(
    find "${1:-.}" -path '*/\.*' -prune -o -type d -print 2> /dev/null \
      | fzf +m \
          --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:hidden:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return
  cd "$dir" || return
}

# zda - including hidden directories
zda() {
  local dir
  dir="$(
    find "${1:-.}" -type d 2> /dev/null \
      | fzf +m \
          --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:hidden:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return
  cd "$dir" || return
}

# zdr - cd to selected parent directory
zdr() {
  local dirs=()
  local parent_dir

  get_parent_dirs() {
    if [[ -d "$1" ]]; then dirs+=("$1"); else return; fi
    if [[ "$1" == '/' ]]; then
      for _dir in "${dirs[@]}"; do echo "$_dir"; done
    else
      get_parent_dirs "$(dirname "$1")"
    fi
  }

  parent_dir="$(
    get_parent_dirs "$(realpath "${1:-$PWD}")" \
      | fzf +m \
          --preview 'tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:hidden:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return

  cd "$parent_dir" || return
}

# zst - cd into the directory from stack
zst() {
  local dir
  dir="$(
    dirs \
      | sed 's#\s#\n#g' \
      | uniq \
      | sed "s#^~#$HOME#" \
      | fzf +s +m -1 -q "$*" \
            --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
            --preview-window='right:hidden:wrap' \
            --bind=ctrl-v:toggle-preview \
            --bind=ctrl-x:toggle-sort \
            --header='(view:ctrl-v) (sort:ctrl-x)' \
  )"
  # check $dir exists for Ctrl-C interrupt
  # or change directory to $HOME (= no value cd)
  if [[ -d "$dir" ]]; then
    cd "$dir" || return
  fi
}

# zdf - cd into the directory of the selected file
zdf() {
  local file
  file="$(fzf +m -q "$*" \
           --preview="${FZF_PREVIEW_CMD}" \
           --preview-window='right:hidden:wrap' \
           --bind=ctrl-v:toggle-preview \
           --bind=ctrl-x:toggle-sort \
           --header='(view:ctrl-v) (sort:ctrl-x)' \
       )"
  cd "$(dirname "$file")" || return
}

# zd - cd into selected directory with options
# The super function of zdd, zda, zdr, zst, zdf, zz
zd() {
  read -r -d '' helptext <<EOF
usage: zd [OPTIONS]
  zd: cd to selected options below
OPTIONS:
  -d [path]: Directory (default)
  -a [path]: Directory included hidden
  -r [path]: Parent directory
  -s [query]: Directory from stack
  -f [query]: Directory of the selected file
  -h: Print this usage
EOF

  usage() {
    echo "$helptext"
  }

  if [[ -z "$1" ]]; then
    # no arg
    zdd
  elif [[ "$1" == '..' ]]; then
    # arg is '..'
    shift
    zdr "$1"
  elif [[ "$1" == '-' ]]; then
    # arg is '-'
    shift
    zst "$*"
  elif [[ "${1:0:1}" != '-' ]]; then
    # first string is not -
    zdd "$(realpath "$1")"
  else
    # args is start from '-'
    while getopts darfszh OPT; do
      case "$OPT" in
        d) shift; zdd  "$1";;
        a) shift; zda "$1";;
        r) shift; zdr "$1";;
        s) shift; zst "$*";;
        f) shift; zdf "$*";;
        h) usage; return 0;;
        *) usage; return 1;;
      esac
    done
  fi
}

## fzf-ghq
fzf-ghq () {
    FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS} --reverse --height=50%"
    local repo="$(ghq list --full-path --exact | fzf --preview="exa --tree --level=2 {1}")"
    local dir=${repo}
    [ -n "${dir}" ] && cd "${dir}"
    zle accept-line
    zle clear-screen
}

zle -N fzf-ghq
bindkey '^h' fzf-ghq

# 1password
## enable plugins
source $XDG_CONFIG_HOME/op/plugins.sh
## enable completion
eval "$(op completion zsh)"
compdef _op op

# aws-vaultの補完
eval "$(aws-vault --completion-script-zsh)"


# alias
## aws-cli
alias aws='awsv2'
## LazyGit
alias lg="lazygit"
## Neovim
alias v="nvim"

## MacのBSD系コマンドをGNU系に置き換える。
case "$OSTYPE" in
    darwin*)
        (( ${+commands[gdate]} )) && alias date='gdate'
        (( ${+commands[gls]} )) && alias ls='gls'
        (( ${+commands[gmkdir]} )) && alias mkdir='gmkdir'
        (( ${+commands[gcp]} )) && alias cp='gcp'
        (( ${+commands[gmv]} )) && alias mv='gmv'
        (( ${+commands[grm]} )) && alias rm='grm'
        (( ${+commands[gdu]} )) && alias du='gdu'
        (( ${+commands[ghead]} )) && alias head='ghead'
        (( ${+commands[gtail]} )) && alias tail='gtail'
        (( ${+commands[gsed]} )) && alias sed='gsed'
        (( ${+commands[ggrep]} )) && alias grep='ggrep'
        (( ${+commands[gfind]} )) && alias find='gfind'
        (( ${+commands[gdirname]} )) && alias dirname='gdirname'
        (( ${+commands[gxargs]} )) && alias xargs='gxargs'
    ;;
esac

## ls
alias ls='ls --color=auto'
alias ll='ls -al'

## 自身のIPアドレスを取得
alias myip='curl https://checkip.amazonaws.com/'
