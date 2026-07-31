module Certvis
  # Writes checker results to JSON atomically (write to a temp file, then
  # rename) so the frontend never reads a half-written file mid-scan.
  module JsonWriter
    module_function

    def write(path, results)
      payload = {
        generated_at: Time.now.utc.iso8601,
        certvis_version: Certvis::VERSION,
        sites: results.sort_by { |r| r.name.downcase }.map { |r| result_to_h(r) }
      }

      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      tmp_path = File.join(dir, ".#{File.basename(path)}.tmp-#{Process.pid}")
      File.write(tmp_path, JSON.pretty_generate(payload))
      File.rename(tmp_path, path)
    end

    def result_to_h(result)
      {
        name: result.name,
        host: result.host,
        port: result.port,
        checked_at: result.checked_at&.iso8601,
        reachable: result.reachable,
        error: result.error,
        not_before: result.not_before&.iso8601,
        not_after: result.not_after&.iso8601,
        hostname_match: result.hostname_match,
        trusted: result.trusted,
        issuer: result.issuer,
        subject: result.subject,
        sans: result.sans
      }
    end
  end
end
