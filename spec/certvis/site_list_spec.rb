# frozen_string_literal: true

require 'tempfile'

RSpec.describe Certvis::SiteList do
  def load(content)
    file = Tempfile.new('sites.lst')
    file.write(content)
    file.close
    described_class.load(file.path)
  ensure
    file.unlink
  end

  it 'parses a bare hostname with the default port' do
    entries = load("example.com\n")
    expect(entries).to contain_exactly(
      have_attributes(name: 'example.com', host: 'example.com', port: Certvis::Checker::DEFAULT_PORT)
    )
  end

  it 'parses host:port' do
    entries = load("example.com:8443\n")
    expect(entries).to contain_exactly(
      have_attributes(name: 'example.com:8443', host: 'example.com', port: 8443)
    )
  end

  it 'strips the scheme and path from a full URL' do
    entries = load("https://example.com/some/path\n")
    expect(entries).to contain_exactly(
      have_attributes(name: 'example.com', host: 'example.com', port: 443)
    )
  end

  it 'strips the scheme and path from a full URL with an explicit port' do
    entries = load("https://example.com:8443/some/path\n")
    expect(entries).to contain_exactly(
      have_attributes(name: 'example.com:8443', host: 'example.com', port: 8443)
    )
  end

  it 'ignores blank lines and comment lines' do
    entries = load("\n# a comment\n  \nexample.com\n")
    expect(entries.map(&:host)).to eq(['example.com'])
  end

  it 'strips a trailing comment from a site line' do
    entries = load("example.com  # this one matters\n")
    expect(entries.map(&:host)).to eq(['example.com'])
  end

  it 'preserves file order across multiple entries' do
    entries = load("zeta.example\nalpha.example\n")
    expect(entries.map(&:host)).to eq(%w[zeta.example alpha.example])
  end

  it 'raises when the file does not exist' do
    expect { described_class.load('/nonexistent/sites.lst') }.to raise_error(ArgumentError, /not found/)
  end
end
