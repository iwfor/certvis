# certvis

Watches the TLS certificates for a list of sites and renders their expiry as
a dashboard. A small Ruby script does the checking and writes a JSON file;
a static HTML page polls that JSON and draws a progress bar per site. No
gems, no build step — just Ruby's standard library and a browser.

## Usage

```
bin/certvis [options]

  -f, --sites-file PATH   Path to sites list (default: sites.lst)
  -o, --output PATH       Path to write JSON output (default: public/certs.json)
  -t, --threads N         Number of checker threads (default: 2)
      --timeout N         Per-connection timeout in seconds (default: 10)
      --retries N         Retry attempts per site on failure (default: 3)
      --backoff N         Base backoff seconds; doubles each retry (default: 2)
  -v, --verbose           Print progress and a summary to stderr
```

Run it once to generate `public/certs.json`:

```
bin/certvis -v
```

Then serve the `public/` directory over HTTP (the page fetches
`certs.json` with `fetch()`, which browsers block from `file://`):

```
ruby -run -e httpd public -p 8000
```

and open http://localhost:8000/.

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

One hostname (or `hostname:port`) per line; `#` starts a comment. See the
bundled `sites.lst` for examples, including a few
[badssl.com](https://badssl.com) endpoints useful for exercising the
expired / wrong-host / untrusted-chain / unreachable code paths.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
