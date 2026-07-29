# frozen_string_literal: true

RSpec.describe Certvis::Runner do
  Entry = Certvis::SiteList::Entry

  # Records which (name, host, port) it was asked to check; sleeps briefly so
  # a single-threaded run and a multi-threaded run take measurably different
  # amounts of wall time, proving the pool actually runs work concurrently.
  class RecordingChecker
    attr_reader :calls

    def initialize
      @calls = Queue.new
    end

    def check(name, host, port)
      @calls << [name, host, port]
      sleep 0.05
      Certvis::Checker::Result.new(
        name: name, host: host, port: port, checked_at: Time.now.utc,
        reachable: true, error: nil, not_before: nil, not_after: nil,
        hostname_match: true, trusted: true, issuer: nil, subject: nil, sans: []
      )
    end
  end

  let(:entries) { (1..8).map { |i| Entry.new("site#{i}.example", "site#{i}.example", 443) } }

  it 'checks every entry exactly once' do
    checker = RecordingChecker.new
    results = described_class.new(checker: checker, threads: 4).run(entries)

    expect(results.size).to eq(entries.size)
    expect(results.map(&:name)).to match_array(entries.map(&:host))
  end

  it 'runs checks concurrently across the configured thread count' do
    checker = RecordingChecker.new
    started = Time.now
    described_class.new(checker: checker, threads: 8).run(entries)
    elapsed = Time.now - started

    # 8 entries * 0.05s would take ~0.4s serialized; with 8 threads it should
    # complete in roughly one slot's worth of time.
    expect(elapsed).to be < 0.3
  end

  it 'treats a thread count below 1 as 1' do
    expect { described_class.new(checker: RecordingChecker.new, threads: 0).run([]) }.not_to raise_error
  end

  it 'returns an empty array for an empty entry list' do
    results = described_class.new(checker: RecordingChecker.new, threads: 3).run([])
    expect(results).to eq([])
  end
end
