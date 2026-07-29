module Certvis
  # Parses sites.lst: one "host" or "host:port" per line. Blank lines and
  # lines starting with # are ignored; trailing "# comment" is stripped.
  class SiteList
    Entry = Struct.new(:name, :host, :port)

    def self.load(path)
      raise ArgumentError, "sites file not found: #{path}" unless File.exist?(path)

      File.readlines(path, chomp: true).each_with_object([]) do |raw, entries|
        line = raw.split('#', 2).first.to_s.strip
        next if line.empty?

        host, port = line.split(':', 2)
        entries << Entry.new(line, host.strip, port ? port.strip.to_i : Checker::DEFAULT_PORT)
      end
    end
  end
end
