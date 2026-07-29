# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Certvis::JsonWriter do
  let(:result_a) do
    Certvis::Checker::Result.new(
      name: 'zeta.example', host: 'zeta.example', port: 443,
      checked_at: Time.utc(2026, 1, 1), reachable: true, error: nil,
      not_before: Time.utc(2025, 12, 1), not_after: Time.utc(2026, 3, 1),
      hostname_match: true, trusted: true,
      issuer: '/CN=Test CA', subject: '/CN=zeta.example', sans: ['zeta.example']
    )
  end

  let(:result_b) do
    Certvis::Checker::Result.new(
      name: 'alpha.example', host: 'alpha.example', port: 443,
      checked_at: Time.utc(2026, 1, 1), reachable: false, error: 'SocketError: fail',
      not_before: nil, not_after: nil, hostname_match: nil, trusted: nil,
      issuer: nil, subject: nil, sans: []
    )
  end

  it 'writes sorted, well-formed JSON with a generated_at timestamp' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'certs.json')
      described_class.write(path, [result_a, result_b])

      payload = JSON.parse(File.read(path))
      expect(payload['generated_at']).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(payload['sites'].map { |s| s['name'] }).to eq(%w[alpha.example zeta.example])
      expect(payload['sites'].first).to include(
        'reachable' => false, 'error' => 'SocketError: fail', 'not_after' => nil
      )
      expect(payload['sites'].last).to include(
        'reachable' => true, 'hostname_match' => true, 'trusted' => true, 'sans' => ['zeta.example']
      )
    end
  end

  it 'creates the target directory if it does not exist yet' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'nested', 'deeper', 'certs.json')
      described_class.write(path, [result_a])
      expect(File.exist?(path)).to be(true)
    end
  end

  it 'writes atomically, leaving no temp file behind' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'certs.json')
      described_class.write(path, [result_a])
      expect(Dir.children(dir)).to eq(['certs.json'])
    end
  end

  it 'overwrites a previous file rather than appending' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'certs.json')
      described_class.write(path, [result_a])
      described_class.write(path, [result_b])
      payload = JSON.parse(File.read(path))
      expect(payload['sites'].size).to eq(1)
    end
  end
end
