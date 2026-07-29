# frozen_string_literal: true

# A minimal self-signed TLS server for exercising Certvis::Checker without
# touching the network. Presents one certificate to every connection
# (SNI is ignored, same as a misconfigured real host), which is exactly what
# lets us test the hostname-mismatch path.
class TlsTestServer
  attr_reader :port

  def initialize(common_name: 'localhost', not_before: Time.now - 86_400, not_after: Time.now + (30 * 86_400))
    @tcp = TCPServer.new('127.0.0.1', 0)
    @port = @tcp.addr[1]
    @ssl_server = OpenSSL::SSL::SSLServer.new(@tcp, build_context(common_name, not_before, not_after))
    @running = true
    @thread = Thread.new { accept_loop }
  end

  def stop
    @running = false
    @ssl_server.close
    @thread.join(1)
  end

  private

  def build_context(common_name, not_before, not_after)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(2**32)
    name = OpenSSL::X509::Name.parse("/CN=#{common_name}")
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = not_before
    cert.not_after = not_after

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension('subjectAltName', "DNS:#{common_name}", false))
    cert.sign(key, OpenSSL::Digest::SHA256.new)

    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert
    ctx.key = key
    ctx
  end

  def accept_loop
    while @running
      begin
        conn = @ssl_server.accept
      rescue StandardError
        break
      end
      conn.close
    end
  end
end
