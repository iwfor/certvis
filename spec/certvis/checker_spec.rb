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
