#compdef certvis
# zsh completion for certvis
# Install: certvis --completions zsh > "${fpath[1]}/_certvis"

_certvis() {
  _arguments \
    '(-f --sites-file)'{-f,--sites-file}'[Path to sites list]:file:_files' \
    '(-o --output)'{-o,--output}'[Path to write JSON output]:file:_files' \
    '(-t --threads)'{-t,--threads}'[Number of checker threads]:threads:' \
    '--timeout[Per-connection timeout in seconds]:seconds:' \
    '--retries[Retry attempts per site on failure]:retries:' \
    '--backoff[Base backoff seconds; doubles each retry]:seconds:' \
    '--preserve-html[Do not overwrite an out-of-date index.html next to --output]' \
    '--no-deploy-html[Never copy index.html next to --output]' \
    '--serve[Serve the output directory over HTTP after writing]' \
    '--port[Port for --serve (default 8000)]:port:' \
    '--completions[Print shell completions and exit]:shell:(bash zsh)' \
    '(-v --verbose)'{-v,--verbose}'[Print progress and a summary to stderr]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_certvis "$@"
