# frozen_string_literal: true

RSpec.describe Certvis::Checker do
  describe 'against a live TLS server' do
    let(:server) { TlsTestServer.new(common_name: 'localhost') }

    after { server.stop }

    it 'reports dates, hostname match, and reachability for a matching host' do
      result = described_class.new(timeout: 2, retries: 0).check('local', 'localhost', server.port)

      expect(result.reachable).to be(true)
      expect(result.error).to be_nil
      expect(result.hostname_match).to be(true)
      expect(result.not_before).to be_a(Time)
      expect(result.not_after).to be_a(Time)
      expect(result.not_after).to be > result.not_before
      expect(result.subject).to include('localhost')
      expect(result.sans).to include('localhost')
    end

    it 'is not trusted, since the cert is self-signed' do
      result = described_class.new(timeout: 2, retries: 0).check('local', 'localhost', server.port)
      expect(result.trusted).to be(false)
    end
  end

  describe 'hostname mismatch' do
    let(:server) { TlsTestServer.new(common_name: 'other.example') }

    after { server.stop }

    it 'reports hostname_match as false when the cert does not cover the host' do
      result = described_class.new(timeout: 2, retries: 0).check('local', 'localhost', server.port)
      expect(result.reachable).to be(true)
      expect(result.hostname_match).to be(false)
    end
  end

  describe 'an expired certificate' do
    let(:server) { TlsTestServer.new(common_name: 'localhost', not_before: Time.now - (60 * 86_400), not_after: Time.now - 86_400) }

    after { server.stop }

    it 'still reports the actual (past) not_after date rather than failing' do
      result = described_class.new(timeout: 2, retries: 0).check('local', 'localhost', server.port)
      expect(result.reachable).to be(true)
      expect(result.not_after).to be < Time.now
    end
  end

  describe 'trusted?' do
    # Expiry and CA trust are independent checks: an expired cert from an
    # otherwise-trusted CA should read as trusted (and just "expired"), not
    # get lumped in with genuinely untrusted-CA/self-signed certs.
    it 'is true for an expired cert whose issuing CA is trusted' do
      ca_key = OpenSSL::PKey::RSA.new(2048)
      ca_cert = OpenSSL::X509::Certificate.new
      ca_cert.version = 2
      ca_cert.serial = 1
      ca_cert.subject = OpenSSL::X509::Name.parse('/CN=Test CA')
      ca_cert.issuer = ca_cert.subject
      ca_cert.public_key = ca_key.public_key
      ca_cert.not_before = Time.now - (365 * 86_400)
      ca_cert.not_after = Time.now + (365 * 86_400)
      ca_ef = OpenSSL::X509::ExtensionFactory.new
      ca_ef.subject_certificate = ca_cert
      ca_ef.issuer_certificate = ca_cert
      ca_cert.add_extension(ca_ef.create_extension('basicConstraints', 'CA:TRUE', true))
      ca_cert.sign(ca_key, OpenSSL::Digest::SHA256.new)

      leaf_key = OpenSSL::PKey::RSA.new(2048)
      leaf_cert = OpenSSL::X509::Certificate.new
      leaf_cert.version = 2
      leaf_cert.serial = 2
      leaf_cert.subject = OpenSSL::X509::Name.parse('/CN=expired.example')
      leaf_cert.issuer = ca_cert.subject
      leaf_cert.public_key = leaf_key.public_key
      leaf_cert.not_before = Time.now - (60 * 86_400)
      leaf_cert.not_after = Time.now - 86_400
      leaf_ef = OpenSSL::X509::ExtensionFactory.new
      leaf_ef.subject_certificate = leaf_cert
      leaf_ef.issuer_certificate = ca_cert
      leaf_cert.add_extension(leaf_ef.create_extension('subjectAltName', 'DNS:expired.example', false))
      leaf_cert.sign(ca_key, OpenSSL::Digest::SHA256.new)

      store = OpenSSL::X509::Store.new
      store.add_cert(ca_cert)
      allow(OpenSSL::X509::Store).to receive(:new).and_return(store)

      checker = described_class.new
      expect(checker.send(:trusted?, leaf_cert, [leaf_cert, ca_cert])).to be(true)
    end
  end

  describe 'an unreachable host' do
    it 'retries and then reports a clear error instead of raising' do
      tcp = TCPServer.new('127.0.0.1', 0)
      free_port = tcp.addr[1]
      tcp.close

      result = described_class.new(timeout: 1, retries: 1, backoff: 1).check('down', '127.0.0.1', free_port)

      expect(result.reachable).to be(false)
      expect(result.error).to be_a(String)
      expect(result.not_before).to be_nil
      expect(result.not_after).to be_nil
    end
  end
end
