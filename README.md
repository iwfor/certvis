# certvis

Watches the TLS certificates for a list of sites and renders their expiry as
a dashboard. A small Ruby script does the checking and writes a JSON file;
a static HTML page polls that JSON and draws a progress bar per site. No
gems, no build step — just Ruby's standard library and a browser.

## Usage

```
bin/certvis [options]

  -f, --sites-file PATH   Path to sites list (default: ./sites.lst)
  -o, --output PATH       Path to write JSON output (default: ./public/certs.json)
  -t, --threads N         Number of checker threads (default: 2)
      --timeout N         Per-connection timeout in seconds (default: 10)
      --retries N         Retry attempts per site on failure (default: 3)
      --backoff N         Base backoff seconds; doubles each retry (default: 2)
      --sync-html         Overwrite index.html next to --output with the bundled copy
      --no-deploy-html    Never copy index.html next to --output
      --serve             Serve the output directory over HTTP after writing
      --port N            Port for --serve (default: 8000)
      --completions [SHELL]  Print bash or zsh completions (default: detect $SHELL) and exit
  -v, --verbose           Print progress and a summary to stderr
```

Run it once to generate `public/certs.json`:

```
bin/certvis -v
```

The page fetches `certs.json` with `fetch()`, which browsers block from
`file://`, so it needs to be served over HTTP. `--serve` does this for you:

```
bin/certvis -v --serve
```

and open http://localhost:8000/. `--serve` needs the `webrick` gem — run
`bundle install` once (see [Development](#development)), or `gem install
webrick`. Pass `--port` to use something other than 8000. This is meant for
local previewing; for production, point any webserver at the output
directory, or keep using `ruby -run -e httpd public -p 8000`.

### Shell completions

```
bin/certvis --completions bash >> ~/.bash_completion   # or wherever bash-completion looks
bin/certvis --completions zsh > "${fpath[1]}/_certvis"
```

Leaving off the shell name (`--completions` alone) detects bash vs. zsh from
`$SHELL`.

## Scheduling

`bin/certvis` does one scan and exits — you control the cadence. The
dashboard itself re-reads `certs.json` every 15 minutes (plus a manual
reload button), so a 15-minute cron cadence keeps it current:

```cron
*/15 * * * * cd /path/to/certvis && bin/certvis >> certvis.log 2>&1
```

Or run it directly whenever you want a refresh. Writes to the output file
are atomic (write-then-rename), so the dashboard never sees a half-written
file mid-scan.

### Running from elsewhere / deploying to a webserver

By default `-f`/`-o` are resolved relative to your **current directory**,
not wherever certvis is installed — so a symlink on `$PATH`, or an alias,
works the way you'd expect: `cd ~/sites/some-project && certvis -v` reads
`~/sites/some-project/sites.lst` and writes
`~/sites/some-project/public/certs.json`, letting you keep a separate
sites.lst (and cron job) per project against a single certvis install.

Wherever `-o` ends up, `index.html` won't be there automatically — it's a
static file, not something regenerated each run. certvis handles this for
you: the first time it writes to a new output directory, it copies its
bundled `index.html` in next to the JSON, resolved from certvis's own
install location regardless of your cwd. Later runs leave that copy alone
(so any edits you make to the deployed page survive), unless you pass
`--sync-html` to force it back to the bundled version, or
`--no-deploy-html` to disable the copy entirely.

## How a site is checked

For each host in `sites.lst`, certvis:

1. Opens a TCP connection and TLS handshake (with SNI set to the hostname),
   retrying with exponential backoff (`--retries` / `--backoff`) on
   connection failures, timeouts, and TLS errors.
2. Reads the leaf certificate's `not_before` / `not_after` dates.
3. Checks whether the certificate is actually valid **for that hostname**
   (`hostname_match`, via SAN/CN — a cert can legitimately cover several
   hostnames) and whether the chain is trusted against the system CA store
   (`trusted`), independently of the date check.

All of this is written to `public/certs.json`. Sites that couldn't be
reached at all get `"reachable": false` and an `"error"` message instead of
dates.

## Dashboard

Sites are sorted expired-first, then "expiring soon" (within 4 weeks),
then alphabetically. Each site's bar fills from certificate issue date to
expiry date, colored by urgency:

| State | Color |
|---|---|
| > 4 weeks to expiry | green |
| 4 → 2 weeks | blends green → yellow → light red |
| ≤ 2 weeks (incl. the last week) | light red |
| expired | dark red |
| couldn't be downloaded | black |

A site whose cert doesn't match its hostname or isn't chain-trusted is
flagged with a warning badge regardless of its date-based color, since an
improperly signed cert is a problem even if the dates look fine.

## sites.lst

One site per line: a bare hostname, `hostname:port`, or a full URL like
`https://hostname/path` (scheme and path are stripped — only the host and
optional port are used). `#` starts a comment. See the bundled `sites.lst`
for examples, including a few [badssl.com](https://badssl.com) endpoints
useful for exercising the expired / wrong-host / untrusted-chain /
unreachable code paths.

## Development

certvis itself is stdlib-only; the `Gemfile` covers `webrick` (for
`--serve`) and `rspec` (for the test suite):

```
bundle install
bundle exec rspec
```

The checker specs spin up a real self-signed TLS server on localhost rather
than mocking OpenSSL, so they exercise the actual handshake, hostname, and
trust logic.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
