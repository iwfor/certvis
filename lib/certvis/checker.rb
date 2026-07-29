module Certvis
  # Connects to a single host over TLS, retrieves its certificate, and
  # reports validity dates plus whether it is properly signed for the host.
  class Checker
    DEFAULT_PORT = 443
    RETRYABLE_ERRORS = [
      Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
      Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, Timeout::Error, EOFError
    ].freeze

    Result = Struct.new(
      :name, :host, :port, :checked_at, :reachable, :error,
      :not_before, :not_after, :hostname_match, :trusted,
      :issuer, :subject, :sans,
      keyword_init: true
    )

    def initialize(timeout: 10, retries: 3, backoff: 2)
      @timeout = timeout
      @retries = retries
      @backoff = backoff
    end

    def check(name, host, port = DEFAULT_PORT)
      attempt = 0
      begin
        attempt += 1
        fetch(name, host, port)
      rescue *RETRYABLE_ERRORS => e
        if attempt <= @retries
          sleep(@backoff**(attempt - 1))
          retry
        end
        error_result(name, host, port, e)
      end
    end

    private

    def fetch(name, host, port)
      checked_at = Time.now.utc
      tcp = Socket.tcp(host, port, connect_timeout: @timeout)
      ssl = nil
      begin
        ctx = OpenSSL::SSL::SSLContext.new
        # Fetch the cert even if untrusted so we can report *why* it failed
        # (trust and hostname match are checked separately below).
        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
        ssl.hostname = host # SNI
        Timeout.timeout(@timeout) { ssl.connect }

        cert = ssl.peer_cert
        chain = ssl.peer_cert_chain || [cert]

        Result.new(
          name: name, host: host, port: port, checked_at: checked_at,
          reachable: true, error: nil,
          not_before: cert.not_before.utc, not_after: cert.not_after.utc,
          hostname_match: OpenSSL::SSL.verify_certificate_identity(cert, host),
          trusted: trusted?(cert, chain),
          issuer: cert.issuer.to_s, subject: cert.subject.to_s,
          sans: subject_alt_names(cert)
        )
      ensure
        ssl&.sysclose rescue nil
        tcp.close rescue nil
      end
    end

    # A cert can legitimately cover multiple hostnames (SANs); trust and
    # hostname match are independent checks, both required for "properly signed".
    def trusted?(cert, chain)
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      store.verify(cert, chain)
    rescue OpenSSL::X509::StoreError
      false
    end

    def subject_alt_names(cert)
      ext = cert.extensions.find { |e| e.oid == 'subjectAltName' }
      return [] unless ext

      ext.value.split(',').map { |entry| entry.split(':', 2).last.to_s.strip }
    end

    def error_result(name, host, port, error)
      Result.new(
        name: name, host: host, port: port, checked_at: Time.now.utc,
        reachable: false, error: "#{error.class}: #{error.message}",
        not_before: nil, not_after: nil, hostname_match: nil, trusted: nil,
        issuer: nil, subject: nil, sans: []
      )
    end
  end
end
