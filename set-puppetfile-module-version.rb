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
    parser.on('-v', '--version=SHA') do |sha|
      opts[:version] = sha
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
  rewriter      = LockPuppetfileModuleVersion.new(opts[:module], opts[:version], opts[:default_branch])
  rewritten     = rewriter.rewrite(buffer, ast)

  File.open("Puppetfile", "w") { |f| f.write(rewritten) }
end

class LockPuppetfileModuleVersion < Parser::TreeRewriter
  def initialize(mod, version, default_branch = nil)
    @mod = mod
    @version = version
    @default_branch = default_branch
  end

  def on_send(node)
    if git_mod?(node)
      if target_mod?(node)
        version_pair = get_pair(node, :branch) || get_pair(node, :commit) || get_pair(node, :ref)
        unless version_pair.nil?
          hashkey = version_pair.children[0].children.first.to_s
          replace(version_pair.location.expression, "#{hashkey}: '#{get_lock_version(node)}'")
        end
      end

      if @default_branch
        default_pair = get_pair(node, :default_branch)
        replace(default_pair.location.expression, "default_branch: '#{@default_branch}'") unless default_pair.nil?
      end
    elsif target_mod?(node)
      replace(node.children[3].location.expression, "'#{@version}'")
    end
  end

  def target_mod?(node)
    node.children[1].eql?(:mod) &&
    get_name(node).eql?(@mod)
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
    @version
  end
end

main
