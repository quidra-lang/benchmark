require_relative 'lexer'

module IncludeSyntax
  STARTS = %w[if ifdef ifndef].freeze
  BRANCHES = %w[elif elifdef elifndef else].freeze
  module_function

  def directive_name(tokens)
    tokens[1].spelling if tokens[0]&.spelling == '#' && tokens[1]&.kind == :identifier
  end

  def guard(lines)
    nonempty = lines.map(&:tokens).reject(&:empty?)
    return nil if nonempty.empty?
    first, last = nonempty.first, nonempty.last
    return nil unless first.length == 3 && directive_name(first) == 'ifndef' && first[2].kind == :identifier
    return nil unless last.length == 2 && directive_name(last) == 'endif'
    depth = 0
    nonempty.each_with_index do |tokens, index|
      name = directive_name(tokens)
      return nil if BRANCHES.include?(name) && depth == 1
      depth += 1 if STARTS.include?(name)
      depth -= 1 if name == 'endif'
      return nil if depth == 0 && index != nonempty.length - 1
    end
    first[2].spelling if depth == 0
  end
end

class SourceFile
  attr_reader :path, :physical_lines, :lines, :guard
  attr_accessor :once, :entered, :skipped, :output_lines, :skipped_lines

  def initialize(path, contents)
    @path, @physical_lines = path, contents.count("\n")
    @lines = Lexer.source(contents)
    @guard = IncludeSyntax.guard(lines)
    @once = false
    @entered = @skipped = @output_lines = @skipped_lines = 0
  end
end

class IncludeManager
  attr_reader :files

  def initialize
    @files = {}
  end

  def search(name, quoted)
    paths = quoted ? [name, "include/#{name}"] : ["include/#{name}"]
    paths.find { |path| File.file?(File.join('input', path)) }
  end

  def load(path)
    files[path] ||= SourceFile.new(path, File.binread(File.join('input', path)))
  end
end
