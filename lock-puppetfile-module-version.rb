#!/usr/bin/env ruby

require 'parser/current'
require 'optparse'

def main
  opts = {}
  ARGV << '-h' if ARGV.empty?
  OptionParser.new do |parser|
    parser.on('-m', '--module=MODULE') do |mod|
      opts[:module] = mod
    end
    parser.on('-c', '--commit=SHA') do |sha|
      opts[:commit] = sha
    end
    parser.on('-d', '--default-branch=DEFAULT') do |default|
      opts[:default_branch] = default
    end
    parser.on("-h", "--help", "Show this message") do
      puts parser
      exit
    end
  end.parse!

  code = File.read('Puppetfile')

  ast           = Parser::CurrentRuby.parse(code)
  buffer        = Parser::Source::Buffer.new('(example)')
  buffer.source = code
  rewriter      = LockPuppetfileModuleVersion.new(opts[:module], opts[:commit], opts[:default_branch])
  rewritten     = rewriter.rewrite(buffer, ast)

  File.open("Puppetfile", "w") { |f| f.write(rewritten) }
end

class LockPuppetfileModuleVersion < Parser::TreeRewriter
  def initialize(mod, commit, default_branch = nil)
    @mod = mod
    @commit = commit
    @default_branch = default_branch
  end

  def on_send(node)
    if target_mod?(node)
      version_pair = get_pair(node, :branch) || get_pair(node, :commit)
      replace(version_pair.location.expression, ":commit => '#{get_lock_version(node)}'") unless version_pair.nil?
    end

    if @default_branch && git_mod?(node)
      default_pair = get_pair(node, :default_branch)
      replace(default_pair.location.expression, ":default_branch => '#{@default_branch}'") unless default_pair.nil?
    end
  end

  def target_mod?(node)
    node.children[1].eql?(:mod) &&
    get_name(node).eql?(@mod) &&
    !node.children[3].children.first.is_a?(String)
  end

  def git_mod?(node)
    node.children[1].eql?(:mod) &&
    !node.children[3].children.first.is_a?(String) &&
    get_pair(node, :git)
  end

  def get_name(node)
    node.children[2].children.first
  end

  def get_pair(node, arg)
    val = node.children[3].children.find do |n|
      n.children[0].children[0].eql?(arg)
    end
  end

  def get_arg(node, arg)
    get_pair(node, arg).children[1].children[0]
  end

  def get_lock_version(node)
    @commit
  end
end

main
