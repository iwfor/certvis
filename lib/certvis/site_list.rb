module Certvis
  # Parses sites.lst: one "host", "host:port", or full URL (e.g.
  # "https://host/path") per line. Blank lines and lines starting with #
  # are ignored; trailing "# comment" is stripped.
  class SiteList
    Entry = Struct.new(:name, :host, :port)

    SCHEME = %r{\A[a-zA-Z][a-zA-Z0-9+.\-]*://}

    def self.load(path)
      raise ArgumentError, "sites file not found: #{path}" unless File.exist?(path)

      File.readlines(path, chomp: true).each_with_object([]) do |raw, entries|
        line = raw.split('#', 2).first.to_s.strip
        next if line.empty?

        line = line.sub(SCHEME, '').split('/', 2).first

        host, port = line.split(':', 2)
        host = host.strip
        port = port&.strip
        name = port ? "#{host}:#{port}" : host
        entries << Entry.new(name, host, port ? port.to_i : Checker::DEFAULT_PORT)
      end
    end
  end
end
