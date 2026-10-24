# frozen_string_literal: true

require 'set'

class Node
  attr_reader :inode
  attr_accessor :parent, :name, :modified

  def initialize(inode, modified)
    @inode, @modified = inode, modified
    @name = ''
  end

  def links = 1
end

class Directory < Node
  attr_reader :entries

  def initialize(inode, modified)
    super
    @entries = {}
  end

  def size = @entries.size
  def tag = 'd'
  def links = 2 + @entries.values.count { |node| node.is_a?(Directory) }
  def children = @entries.keys.sort.map { |name| @entries.fetch(name) }
end

class FileNode < Node
  attr_accessor :lines

  def initialize(inode, modified, lines = [])
    super(inode, modified)
    @lines = lines.dup.freeze
  end

  def size = @lines.sum { |line| line.bytesize + 1 }
  def tag = 'f'
end

class LinkNode < Node
  attr_reader :target

  def initialize(inode, modified, target)
    super(inode, modified)
    @target = target.freeze
  end

  def size = @target.bytesize
  def tag = 'l'
end

Resolution = Data.define(:node, :reason, :creation_parent, :creation_name) do
  def initialize(node: nil, reason: nil, creation_parent: nil, creation_name: nil)
    super(node:, reason:, creation_parent:, creation_name:)
  end

  def absent? = !creation_parent.nil?
end
Options = Data.define(:flags, :paths) do
  def has?(flag) = flags.include?(flag)
end
Listed = Data.define(:name, :node)
Input = Data.define(:lines, :name)

class Output
  attr_reader :lines

  def initialize(terminal, direct)
    @terminal, @direct = terminal, direct
    @lines = []
  end

  def emit(line)
    if @direct
      @terminal.puts(line)
    else
      @lines << line.freeze
    end
  end

  def print(template, *args) = emit(format(template, *args))
  def error(template, *args) = @terminal.puts(format(template, *args))
end

def options(args)
  flags = Set.new
  at = 0
  while at < args.length && args[at].start_with?('-')
    args[at][1..].each_char { |flag| flags.add(flag) }
    at += 1
  end
  Options.new(flags.freeze, args.drop(at).freeze)
end

def last_component(path) = path[(path.rindex('/') || -1) + 1..]
def invalid_source?(path) = ['', '.', '..'].include?(last_component(path))
def join_path(path, name) = path == '/' ? "/#{name}" : "#{path}/#{name}"

class Shell
  MISSING = 'No such file or directory'
  NOT_DIRECTORY = 'Not a directory'
  LOOP = 'Too many levels of symbolic links'

  def initialize
    @root = Directory.new(1, 0)
    @root.parent = @root
    @current = @root
    @previous = nil
    @clock = 0
    @next_inode = 2
  end

  def absolute(node)
    parts = []
    until node.equal?(@root)
      parts << node.name
      node = node.parent
    end
    '/' + parts.reverse.join('/')
  end

  def descendant?(node, ancestor)
    loop do
      return true if node.equal?(ancestor)
      return false if node.equal?(@root)
      node = node.parent
    end
  end

  def add(parent, name, node)
    parent.entries[name] = node
    parent.modified = @clock
    node.parent = parent
    node.name = name.freeze
  end

  def create(parent, name, type, payload = nil)
    node = if type == Directory
             Directory.new(@next_inode, @clock)
           elsif type == FileNode
             FileNode.new(@next_inode, @clock, payload || [])
           else
             LinkNode.new(@next_inode, @clock, payload)
           end
    @next_inode += 1
    add(parent, name, node)
    node
  end

  def detach(node)
    node.parent.entries.delete(node.name)
    node.parent.modified = @clock
  end

  def write(file, lines, append = false)
    file.lines = (append ? file.lines + lines : lines.dup).freeze
    file.modified = @clock
  end

  def resolve(path, follow = true, parents = false)
    expansions = 0
    walk = lambda do |text, base, follow_final, original|
      node = text.start_with?('/') ? @root : base
      parts = text.split('/').reject(&:empty?)
      parts.each_with_index do |part, i|
        return Resolution.new(reason: NOT_DIRECTORY) unless node.is_a?(Directory)
        next if part == '.'
        if part == '..'
          node = node.parent
          next
        end
        last = i + 1 == parts.length
        child = node.entries[part]
        unless child
          if original && last
            return Resolution.new(reason: MISSING, creation_parent: node, creation_name: part)
          end
          return Resolution.new(reason: MISSING) unless original && parents
          child = create(node, part, Directory)
        end
        if child.is_a?(LinkNode) && (!last || follow_final)
          expansions += 1
          return Resolution.new(reason: LOOP) if expansions > 8
          result = walk.call(child.target, node, true, false)
          return result unless result.node
          child = result.node
        end
        node = child
      end
      Resolution.new(node:)
    end
    walk.call(path, @current, follow, true)
  end

  def clone_node(source, parent, name)
    payload = source.is_a?(FileNode) ? source.lines : (source.target if source.is_a?(LinkNode))
    copy = create(parent, name, source.class, payload)
    source.children.each { |child| clone_node(child, copy, child.name) } if source.is_a?(Directory)
  end

  def move(source_path, destination, out)
    problem = ->(path, reason) { out.error("mv: cannot move '%s' to '%s': %s", source_path, path, reason) }
    if invalid_source?(source_path)
      problem.call(destination, 'Invalid argument')
      return
    end
    result = resolve(source_path, false)
    source = result.node
    unless source
      out.error("mv: cannot stat '%s': %s", source_path, result.reason)
      return
    end
    destination_node = resolve(destination).node
    if destination_node.is_a?(Directory)
      parent, name = destination_node, last_component(source_path)
      target = join_path(destination, name)
    else
      result = resolve(destination, false)
      if result.absent?
        parent, name = result.creation_parent, result.creation_name
      elsif result.node
        parent, name = result.node.parent, result.node.name
      else
        problem.call(destination, result.reason)
        return
      end
      target = destination
    end
    existing = parent.entries[name]
    if source.is_a?(Directory) && descendant?(parent, source)
      out.error("mv: cannot move '%s' to a subdirectory of itself, '%s'", source_path, target)
    elsif existing.equal?(source)
      out.error("mv: '%s' and '%s' are the same file", source_path, target)
    elsif existing && source.is_a?(Directory) && !existing.is_a?(Directory)
      out.error("mv: cannot overwrite non-directory '%s' with directory '%s'", target, source_path)
    elsif !source.is_a?(Directory) && existing.is_a?(Directory)
      out.error("mv: cannot overwrite directory '%s' with non-directory '%s'", target, source_path)
    elsif existing.is_a?(Directory) && !existing.entries.empty?
      problem.call(target, 'Directory not empty')
    elsif existing.equal?(@current)
      problem.call(target, 'Device or resource busy')
    else
      detach(existing) if existing
      detach(source)
      add(parent, name, source)
    end
  end

  def copy(source_path, destination, recursive, out)
    problem = ->(path, reason) { out.error("cp: cannot copy '%s' to '%s': %s", source_path, path, reason) }
    if invalid_source?(source_path)
      problem.call(destination, 'Invalid argument')
      return
    end
    result = resolve(source_path)
    source = result.node
    unless source
      out.error("cp: cannot stat '%s': %s", source_path, result.reason)
      return
    end
    if source.is_a?(Directory) && !recursive
      out.error("cp: -r not specified; omitting directory '%s'", source_path)
      return
    end
    result = resolve(destination)
    if !result.node && !result.absent?
      problem.call(destination, result.reason)
      return
    end
    target = result.node.is_a?(Directory) ? join_path(destination, last_component(source_path)) : destination
    result = resolve(target, !source.is_a?(Directory))
    if source.is_a?(Directory)
      if result.node
        problem.call(target, 'File exists')
      elsif descendant?(result.creation_parent, source)
        out.error("cp: cannot copy a directory, '%s', into itself, '%s'", source_path, target)
      else
        clone_node(source, result.creation_parent, result.creation_name)
      end
    elsif result.absent?
      create(result.creation_parent, result.creation_name, FileNode, source.lines)
    elsif result.node.equal?(source)
      out.error("cp: '%s' and '%s' are the same file", source_path, target)
    elsif result.node.is_a?(Directory)
      out.error("cp: cannot overwrite directory '%s' with non-directory '%s'", target, source_path)
    elsif result.node.is_a?(FileNode)
      write(result.node, source.lines)
    else
      problem.call(target, result.reason)
    end
  end

  def listing(opts, out)
    paths = opts.paths.empty? ? ['.'] : opts.paths
    paths.each do |path|
      result = resolve(path, !opts.has?('l'))
      node = result.node
      unless node
        out.error("ls: cannot access '%s': %s", path, result.reason)
        next
      end
      if node.is_a?(Directory)
        out.emit("#{path}:") if paths.size > 1
        entries = opts.has?('a') ? [Listed.new('.', node), Listed.new('..', node.parent)] : []
        node.children.each do |child|
          entries << Listed.new(child.name, child) if opts.has?('a') || !child.name.start_with?('.')
        end
      else
        entries = [Listed.new(path, node)]
      end
      entries = entries.each_with_index.sort_by { |entry, i| [-entry.node.modified, i] }.map(&:first) if opts.has?('t')
      entries.reverse! if opts.has?('r')
      widths = [1, 1, 1]
      entries.each do |entry|
        [entry.node.links, entry.node.size, entry.node.modified].each_with_index do |number, i|
          widths[i] = [widths[i], number.to_s.length].max
        end
      end
      entries.each do |entry|
        unless opts.has?('l')
          out.emit(entry.name)
          next
        end
        item = entry.node
        numbers = [item.links, item.size, item.modified].each_with_index.map { |number, i| number.to_s.rjust(widths[i]) }.join(' ')
        suffix = item.is_a?(LinkNode) ? " -> #{item.target}" : ''
        out.emit("#{item.is_a?(FileNode) ? '-' : item.tag} #{numbers} #{entry.name}#{suffix}")
      end
    end
  end

  def walk(node, path, depth, limit, &visit)
    visit.call(node, path, depth)
    if node.is_a?(Directory) && depth < limit
      node.children.each { |child| walk(child, join_path(path, child.name), depth + 1, limit, &visit) }
    end
  end

  def find(args, out)
    explicit = args.first && !args.first.start_with?('-')
    path = explicit ? args.first : '.'
    tests = args.drop(explicit ? 1 : 0).each_slice(2).to_h
    result = resolve(path)
    unless result.node
      out.error("find: '%s': %s", path, result.reason)
      return
    end
    walk(result.node, path, 0, tests.fetch('-maxdepth', '1000').to_i) do |node, display, depth|
      name = depth.zero? ? (path == '/' ? '/' : last_component(path)) : node.name
      if (!tests.key?('-name') || glob_match?(tests['-name'], name)) && (!tests.key?('-type') || tests['-type'] == node.tag)
        out.emit(display)
      end
    end
  end

  def usage(node, path, show, opts, out)
    total = if node.is_a?(Directory)
              node.children.sum do |child|
                usage(child, join_path(path, child.name), show && !opts.has?('s') && (child.is_a?(Directory) || opts.has?('a')), opts, out)
              end
            else
              node.size
            end
    out.print('%d %s', total, path) if show
    total
  end

  def disk_usage(opts, out)
    (opts.paths.empty? ? ['.'] : opts.paths).each do |path|
      result = resolve(path)
      if result.node
        usage(result.node, path, true, opts, out)
      else
        out.error("du: cannot access '%s': %s", path, result.reason)
      end
    end
  end

  def draw_tree(directory, prefix, all, counts, out)
    children = directory.children.select { |node| all || !node.name.start_with?('.') }
    children.each_with_index do |child, i|
      last = i + 1 == children.length
      suffix = child.is_a?(LinkNode) ? " -> #{child.target}" : ''
      out.emit(prefix + (last ? '`-- ' : '|-- ') + child.name + suffix)
      if child.is_a?(Directory)
        counts[0] += 1
        draw_tree(child, prefix + (last ? '    ' : '|   '), all, counts, out)
      else
        counts[1] += 1
      end
    end
  end

  def tree(opts, out)
    path = opts.paths.first || '.'
    result = resolve(path)
    unless result.node
      out.error('tree: %s: %s', path, result.reason)
      return
    end
    unless result.node.is_a?(Directory)
      out.error('tree: %s: Not a directory', path)
      return
    end
    out.emit(path)
    counts = [0, 0]
    draw_tree(result.node, '', opts.has?('a'), counts, out)
    out.print('%d %s, %d %s', counts[0], counts[0] == 1 ? 'directory' : 'directories', counts[1], counts[1] == 1 ? 'file' : 'files')
  end

  def read_inputs(command, paths, input, out)
    if paths.empty?
      yield Input.new(input, nil)
      return
    end
    paths.each do |path|
      result = resolve(path)
      if !result.node
        out.error('%s: %s: %s', command, path, result.reason)
      elsif result.node.is_a?(Directory)
        out.error('%s: %s: Is a directory', command, path)
      else
        yield Input.new(result.node.lines, path)
      end
    end
  end

  def text_command(command, args, input, out)
    opts = options(args)
    case command
    when 'grep'
      pattern = opts.has?('i') ? opts.paths.first.downcase : opts.paths.first
      paths = opts.paths.drop(1)
      named = opts.has?('r') || paths.size > 1
      consume = lambda do |part|
        prefix = named ? "#{part.name}:" : ''
        selected = 0
        part.lines.each_with_index do |line, i|
          comparison = opts.has?('i') ? line.downcase : line
          next if comparison.include?(pattern) == opts.has?('v')
          selected += 1
          out.emit(prefix + (opts.has?('n') ? "#{i + 1}:" : '') + line) unless opts.has?('c')
        end
        out.emit(prefix + selected.to_s) if opts.has?('c')
      end
      if !opts.has?('r')
        read_inputs(command, paths, input, out, &consume)
      else
        (paths.empty? ? ['.'] : paths).each do |path|
          result = resolve(path)
          if result.node
            walk(result.node, path, 0, 1000) do |node, display, _depth|
              consume.call(Input.new(node.lines, display)) if node.is_a?(FileNode)
            end
          else
            out.error('grep: %s: %s', path, result.reason)
          end
        end
      end
    when 'sort'
      lines = []
      read_inputs(command, opts.paths, input, out) { |part| lines.concat(part.lines) }
      lines.sort! do |a, b|
        comparison = opts.has?('n') ? numeric_prefix(a) <=> numeric_prefix(b) : 0
        comparison.zero? ? a <=> b : comparison
      end
      lines.reverse! if opts.has?('r')
      lines.each { |line| out.emit(line) }
    when 'wc'
      all = %w[l w c].none? { |flag| opts.has?(flag) }
      report = lambda do |counts, name|
        fields = (0..2).select { |i| all || opts.has?('lwc'[i]) }.map { |i| counts[i].to_s }
        out.emit(fields.join(' ') + (name.nil? ? '' : " #{name}"))
      end
      totals = [0, 0, 0]
      read_inputs(command, opts.paths, input, out) do |part|
        counts = [part.lines.size, 0, 0]
        part.lines.each do |line|
          counts[2] += line.bytesize + 1
          inside = false
          line.each_byte do |character|
            counts[1] += 1 if character != 32 && !inside
            inside = character != 32
          end
        end
        3.times { |i| totals[i] += counts[i] }
        report.call(counts, part.name)
      end
      report.call(totals, 'total') if opts.paths.size > 1
    when 'head', 'tail'
      explicit = args.first == '-n'
      raw = explicit ? args[1] : '10'
      special = raw.start_with?('-', '+')
      count = (special ? raw[1..] : raw).to_i
      read_inputs(command, args.drop(explicit ? 2 : 0), input, out) do |part|
        first, ending = 0, part.lines.length
        if command == 'head'
          ending = special ? [0, ending - count].max : [ending, count].min
        else
          first = special ? [ending, [0, count - 1].max].min : [0, ending - count].max
        end
        (first...ending).each { |i| out.emit(part.lines[i]) }
      end
    else
      read_inputs(command, opts.paths, input, out) do |part|
        if command == 'cat'
          part.lines.each { |line| out.emit(line) }
          next
        end
        first = 0
        while first < part.lines.length
          ending = first + 1
          ending += 1 while ending < part.lines.length && part.lines[first] == part.lines[ending]
          out.emit((opts.has?('c') ? "#{ending - first} " : '') + part.lines[first])
          first = ending
        end
      end
    end
  end

  def execute(text, input, out)
    words = text.split(' ')
    command, args = words.first, words.drop(1)
    opts = options(args)
    case command
    when 'pwd' then out.emit(absolute(@current))
    when 'echo' then out.emit(text[5..])
    when 'cd'
      path = args.first || '/'
      back = path == '-'
      if back
        unless @previous
          out.error('cd: OLDPWD not set')
          return
        end
        path = @previous
      end
      result = resolve(path)
      if !result.node
        out.error('cd: %s: %s', path, result.reason)
      elsif !result.node.is_a?(Directory)
        out.error('cd: %s: Not a directory', path)
      else
        @previous = absolute(@current).freeze
        @current = result.node
        out.emit(absolute(@current)) if back
      end
    when 'mkdir'
      opts.paths.each do |path|
        result = resolve(path, false, opts.has?('p'))
        if result.absent?
          create(result.creation_parent, result.creation_name, Directory)
        elsif !result.node
          out.error("mkdir: cannot create directory '%s': %s", path, result.reason)
        elsif !opts.has?('p') || !resolve(path).node.is_a?(Directory)
          out.error("mkdir: cannot create directory '%s': File exists", path)
        end
      end
    when 'touch'
      args.each do |path|
        result = resolve(path)
        if result.absent?
          create(result.creation_parent, result.creation_name, FileNode)
        elsif result.node
          result.node.modified = @clock
        else
          out.error("touch: cannot touch '%s': %s", path, result.reason)
        end
      end
    when 'ls' then listing(opts, out)
    when 'stat'
      args.each do |path|
        result = resolve(path, false)
        node = result.node
        unless node
          out.error("stat: cannot stat '%s': %s", path, result.reason)
          next
        end
        kind = case node
               when Directory then 'directory'
               when LinkNode then 'symbolic link'
               else node.lines.empty? ? 'regular empty file' : 'regular file'
               end
        out.print('%s: %s, size %d, inode %d, links %d, modified %d', path, kind, node.size, node.inode, node.links, node.modified)
      end
    when 'rm', 'rmdir'
      directory_only = command == 'rmdir'
      opts.paths.each do |path|
        dot = ['.', '..'].include?(last_component(path))
        if dot && !directory_only
          out.error("rm: refusing to remove '.' or '..' directory: skipping '%s'", path)
          next
        end
        problem = nil
        if dot
          problem = 'Invalid argument'
        else
          result = resolve(path, false)
          node = result.node
          if !node
            next if !directory_only && opts.has?('f') && result.reason == MISSING
            problem = result.reason
          elsif directory_only && !node.is_a?(Directory)
            problem = 'Not a directory'
          elsif !directory_only && node.is_a?(Directory) && !opts.has?('r')
            problem = 'Is a directory'
          elsif descendant?(@current, node)
            problem = 'Device or resource busy'
          elsif directory_only && !node.entries.empty?
            problem = 'Directory not empty'
          else
            detach(node)
          end
        end
        out.error(directory_only ? "rmdir: failed to remove '%s': %s" : "rm: cannot remove '%s': %s", path, problem) if problem
      end
    when 'mv', 'cp'
      destination = opts.paths.last
      if opts.paths.size > 2 && !resolve(destination).node.is_a?(Directory)
        out.error("%s: target '%s' is not a directory", command, destination)
        return
      end
      opts.paths[0...-1].each do |source|
        command == 'mv' ? move(source, destination, out) : copy(source, destination, opts.has?('r'), out)
      end
    when 'ln'
      path = args[2]
      result = resolve(path, false)
      if result.absent?
        create(result.creation_parent, result.creation_name, LinkNode, args[1])
      else
        out.error("ln: failed to create symbolic link '%s': %s", path, result.node ? 'File exists' : result.reason)
      end
    when 'readlink', 'realpath'
      path = args.first
      result = resolve(path, command == 'realpath')
      if !result.node
        out.error('%s: %s: %s', command, path, result.reason)
      elsif command == 'realpath'
        out.emit(absolute(result.node))
      elsif result.node.is_a?(LinkNode)
        out.emit(result.node.target)
      else
        out.error('readlink: %s: Invalid argument', path)
      end
    when 'find' then find(args, out)
    when 'du' then disk_usage(opts, out)
    when 'tree' then tree(opts, out)
    when 'cat', 'wc', 'head', 'tail', 'grep', 'sort', 'uniq' then text_command(command, args, input, out)
    else out.error('%s: command not found', command)
    end
  end

  def process(line, terminal)
    @clock += 1
    terminal.puts("#{absolute(@current)}$ #{line}")
    pipeline = line
    redirect = nil
    marker = line.index(' >')
    if marker
      pipeline = line[0...marker]
      append = line[marker..].start_with?(' >> ')
      path = line[marker + (append ? 4 : 3)..]
      result = resolve(path)
      if result.absent?
        redirect = create(result.creation_parent, result.creation_name, FileNode)
      elsif result.node.is_a?(FileNode)
        redirect = result.node
        write(redirect, []) unless append
      else
        terminal.puts("sh: #{path}: #{result.node ? 'Is a directory' : result.reason}")
        return
      end
    end
    commands = pipeline.split(' | ')
    input = [].freeze
    commands.each_with_index do |command, i|
      out = Output.new(terminal, i + 1 == commands.size && redirect.nil?)
      execute(command, input, out)
      input = out.lines.freeze
    end
    write(redirect, input, true) if redirect && !input.empty?
  end
end

def glob_match?(pattern, text)
  previous = Array.new(text.length + 1, false)
  previous[0] = true
  pattern.each_char do |character|
    following = Array.new(previous.length, false)
    following[0] = character == '*' && previous[0]
    text.length.times do |i|
      following[i + 1] = if character == '*'
                           previous[i + 1] || following[i]
                         else
                           previous[i] && (character == '?' || character == text[i])
                         end
    end
    previous = following
  end
  previous[text.length]
end

def numeric_prefix(text) = text[/\A-?\d+/]&.to_i || 0

shell = Shell.new
$stdin.each_line do |raw|
  line = raw.chomp.freeze
  break if line == 'exit'
  shell.process(line, $stdout)
end
