# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'net/http'

RSpec.describe 'bin/certvis' do
  let(:bin) { File.expand_path('../bin/certvis', __dir__) }

  def run(*args, chdir:)
    Open3.capture3(RbConfig.ruby, bin, *args, chdir: chdir)
  end

  it 'prints usage for --help' do
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = run('--help', chdir: dir)
      expect(status).to be_success
      expect(stdout).to include('Usage: certvis')
    end
  end

  it 'prints bash completions' do
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = run('--completions', 'bash', chdir: dir)
      expect(status).to be_success
      expect(stdout).to include('_certvis')
      expect(stdout).to include('complete -F _certvis certvis')
    end
  end

  it 'prints zsh completions' do
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = run('--completions', 'zsh', chdir: dir)
      expect(status).to be_success
      expect(stdout).to include('#compdef certvis')
    end
  end

  it 'fails cleanly for an unsupported completion shell' do
    Dir.mktmpdir do |dir|
      _stdout, stderr, status = run('--completions', 'fish', chdir: dir)
      expect(status).not_to be_success
      expect(stderr).to include('fish')
    end
  end

  it 'checks a real site, writes JSON, and deploys index.html relative to cwd' do
    server = TlsTestServer.new(common_name: 'localhost')
    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), "localhost:#{server.port}\n")

        _stdout, stderr, status = run('-v', chdir: dir)
        expect(status).to be_success, stderr

        json_path = File.join(dir, 'public', 'certs.json')
        html_path = File.join(dir, 'public', 'index.html')
        expect(File.exist?(json_path)).to be(true)
        expect(File.exist?(html_path)).to be(true)

        payload = JSON.parse(File.read(json_path))
        expect(payload['sites'].size).to eq(1)
        expect(payload['sites'].first['reachable']).to be(true)
      end
    ensure
      server.stop
    end
  end

  it 'serves the output directory over HTTP with --serve' do
    server = TlsTestServer.new(common_name: 'localhost')
    free_tcp = TCPServer.new('127.0.0.1', 0)
    http_port = free_tcp.addr[1]
    free_tcp.close

    pid = nil
    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), "localhost:#{server.port}\n")

        pid = Process.spawn(RbConfig.ruby, bin, '--serve', '--port', http_port.to_s, chdir: dir, out: File::NULL, err: File::NULL)

        response = nil
        20.times do
          begin
            response = Net::HTTP.get_response(URI("http://127.0.0.1:#{http_port}/certs.json"))
            break
          rescue Errno::ECONNREFUSED
            sleep 0.1
          end
        end

        expect(response).not_to be_nil
        expect(response.code).to eq('200')
        expect(JSON.parse(response.body)['sites'].size).to eq(1)
      end
    ensure
      server.stop
      if pid
        Process.kill('INT', pid)
        Process.wait(pid)
      end
    end
  end
end
