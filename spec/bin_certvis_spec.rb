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

  it 'lists problem sites under -v (self-signed, wrong host, unreachable)' do
    good_server = TlsTestServer.new(common_name: 'localhost')
    mismatched_server = TlsTestServer.new(common_name: 'other.example')
    tcp = TCPServer.new('127.0.0.1', 0)
    dead_port = tcp.addr[1]
    tcp.close

    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), <<~SITES)
          localhost:#{good_server.port}
          localhost:#{mismatched_server.port}
          127.0.0.1:#{dead_port}
        SITES

        _stdout, stderr, status = run('-v', '--retries', '0', chdir: dir)
        expect(status).to be_success, stderr

        expect(stderr).to include('Problems:')
        expect(stderr).to match(/localhost:#{good_server.port}: self-signed/)
        expect(stderr).to match(/localhost:#{mismatched_server.port}: wrong host/)
        expect(stderr).to match(/127\.0\.0\.1:#{dead_port}: unreachable:/)
      end
    ensure
      good_server.stop
      mismatched_server.stop
    end
  end

  it 'resyncs an out-of-date deployed index.html by default' do
    server = TlsTestServer.new(common_name: 'localhost')
    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), "localhost:#{server.port}\n")
        html_path = File.join(dir, 'public', 'index.html')

        run('-v', chdir: dir)
        FileUtils.mkdir_p(File.dirname(html_path))
        File.write(html_path, 'stale copy')

        _stdout, stderr, status = run('-v', chdir: dir)
        expect(status).to be_success, stderr
        expect(stderr).to include('Updated')
        expect(File.read(html_path)).not_to eq('stale copy')
      end
    ensure
      server.stop
    end
  end

  it 'leaves an out-of-date deployed index.html alone with --preserve-html' do
    server = TlsTestServer.new(common_name: 'localhost')
    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), "localhost:#{server.port}\n")
        html_path = File.join(dir, 'public', 'index.html')

        run('-v', chdir: dir)
        FileUtils.mkdir_p(File.dirname(html_path))
        File.write(html_path, 'stale copy')

        _stdout, stderr, status = run('-v', '--preserve-html', chdir: dir)
        expect(status).to be_success, stderr
        expect(stderr).not_to include('Updated')
        expect(File.read(html_path)).to eq('stale copy')
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

  it 're-scans on a schedule with --serve --interval' do
    server = TlsTestServer.new(common_name: 'localhost')
    free_tcp = TCPServer.new('127.0.0.1', 0)
    http_port = free_tcp.addr[1]
    free_tcp.close

    pid = nil
    begin
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sites.lst'), "localhost:#{server.port}\n")
        json_path = File.join(dir, 'public', 'certs.json')

        pid = Process.spawn(
          RbConfig.ruby, bin, '--serve', '--port', http_port.to_s, '--interval', '1',
          chdir: dir, out: File::NULL, err: File::NULL
        )

        first_generated_at = nil
        20.times do
          break if File.exist?(json_path) && (first_generated_at = JSON.parse(File.read(json_path))['generated_at'])

          sleep 0.1
        end
        expect(first_generated_at).not_to be_nil

        later_generated_at = nil
        30.times do
          later_generated_at = JSON.parse(File.read(json_path))['generated_at']
          break if later_generated_at != first_generated_at

          sleep 0.2
        end

        expect(later_generated_at).not_to eq(first_generated_at)
      end
    ensure
      server.stop
      if pid
        Process.kill('TERM', pid)
        Process.wait(pid)
      end
    end
  end
end
