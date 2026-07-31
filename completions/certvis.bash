# bash completion for certvis
# Install: source this file, or copy it into your bash-completion.d directory.
#   certvis --completions bash >> ~/.bash_completion

_certvis() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  opts="-f --sites-file -o --output -t --threads --timeout --retries --backoff \
--preserve-html --no-deploy-html --serve --port --interval --completions -v --verbose -h --help"

  case "$prev" in
    -f | --sites-file | -o | --output)
      COMPREPLY=($(compgen -f -- "$cur"))
      return 0
      ;;
    --completions)
      COMPREPLY=($(compgen -W "bash zsh" -- "$cur"))
      return 0
      ;;
    -t | --threads | --timeout | --retries | --backoff | --port | --interval)
      return 0
      ;;
  esac

  COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

complete -F _certvis certvis
