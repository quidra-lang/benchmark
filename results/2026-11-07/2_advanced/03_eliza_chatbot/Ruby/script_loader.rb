require 'set'

module ScriptLoader
  WORD = /\A[a-z0-9](?:[a-z0-9']*[a-z0-9])?\z/
  REFERENCE = /\A\([0-9]\)\z/
  GLOBALS = %w[INITIAL FINAL QUIT STOP DEFAULT QUESTION REPEAT MEMSIZE PERSIST PRE POST SYNON].freeze
  ITEMS = %w[REASM GOTO NEWKEY RESTATE].freeze
  RULES = %w[DECOMP MEMORY].freeze
  TEXTS = %w[INITIAL FINAL DEFAULT QUESTION REPEAT REASM].freeze
  DIRECTIVES = (GLOBALS + ITEMS + RULES + ['KEY']).freeze

  def self.word?(text)
    WORD.match?(text)
  end

  def self.pattern_element?(text)
    text == '*' || text == '#' || word?(text) || text.start_with?('@') && word?(text[1..])
  end

  def self.valid_arguments?(name, arguments)
    return !arguments.empty? if TEXTS.include?(name)

    case name
    when 'QUIT', 'STOP'
      !arguments.empty? && arguments.all? { |word| word?(word) }
    when 'PRE', 'SYNON'
      arguments.length >= 2 && arguments.all? { |word| word?(word) }
    when 'POST'
      arguments.length >= 2 && word?(arguments.first)
    when 'MEMSIZE'
      arguments.length == 1 && /\A[0-9]{1,2}\z/.match?(arguments.first) && arguments.first.to_i.between?(1, 20)
    when 'PERSIST'
      arguments.length == 1 && %w[cycles memory].include?(arguments.first)
    when 'KEY'
      arguments.length == 2 && word?(arguments.first) && /\A[0-9]{1,2}\z/.match?(arguments.last)
    when 'DECOMP', 'MEMORY'
      !arguments.empty? && arguments.all? { |element| pattern_element?(element) }
    when 'GOTO'
      arguments.length == 1 && word?(arguments.first)
    when 'NEWKEY'
      arguments.empty?
    when 'RESTATE'
      return false unless arguments.length >= 2 && word?(arguments.first)

      arguments.drop(1).all? do |argument|
        word?(argument) || REFERENCE.match?(argument)
      end
    end
  end

  def self.load(path)
    script = { lists: %w[INITIAL FINAL DEFAULT QUESTION REPEAT].to_h { |name| [name, []] },
               keywords: {}, groups: {}, pre: {}, post: {}, quit: Set.new, stop: Set.new,
               persist: Set.new, capacity: 3, diagnostics: [] }
    current_keyword = nil
    current_rule = nil
    persistence_lines = {}
    capacity_line = nil
    File.foreach(path, chomp: true).with_index(1) do |line, number|
      next if line.empty? || line.start_with?('#')

      name, *arguments = line.split(' ')
      text = line.partition(' ')[2]
      if GLOBALS.include?(name) || name == 'KEY'
        current_keyword = nil
        current_rule = nil
      elsif RULES.include?(name)
        next if current_keyword == :ignoring

        current_rule = nil
      elsif ITEMS.include?(name)
        next if current_keyword == :ignoring
      end
      code = message = nil
      if !DIRECTIVES.include?(name)
        code, message = 'SYNTAX', "unknown directive #{name}"
      elsif !valid_arguments?(name, arguments)
        code, message = 'SYNTAX', "bad arguments for #{name}"
      elsif RULES.include?(name) && current_keyword.nil?
        code, message = 'ORPHAN', "#{name} without KEY"
      elsif name == 'REASM' && current_rule.nil?
        code, message = 'ORPHAN', 'REASM without DECOMP or MEMORY'
      elsif %w[GOTO NEWKEY RESTATE].include?(name) && (current_rule.nil? || current_rule[:kind] == 'memory')
        code, message = 'ORPHAN', "#{name} without DECOMP"
      else
        collection = case name
                     when 'KEY' then script[:keywords]
                     when 'SYNON' then script[:groups]
                     when 'PRE' then script[:pre]
                     when 'POST' then script[:post]
                     end
        old_line = collection&.dig(arguments.first, :line)
        old_line = persistence_lines[arguments.first] if name == 'PERSIST'
        old_line = capacity_line if name == 'MEMSIZE'
        if old_line
          code = 'DUPLICATE'
          subject = name == 'MEMSIZE' ? name : "#{name} #{arguments.first}"
          message = "#{subject} first defined at line #{old_line}"
          current_keyword = :ignoring if name == 'KEY'
        end
      end
      if code
        script[:diagnostics] << { line: number, code: code, message: message }
        next
      end
      case name
      when 'INITIAL', 'FINAL', 'DEFAULT', 'QUESTION', 'REPEAT'
        script[:lists][name] << text
      when 'QUIT', 'STOP'
        script[name.downcase.to_sym].merge(arguments)
      when 'MEMSIZE'
        capacity_line = number
        script[:capacity] = arguments.first.to_i
      when 'PERSIST'
        persistence_lines[arguments.first] = number
        script[:persist].add(arguments.first)
      when 'PRE', 'POST'
        script[name.downcase.to_sym][arguments.first] = { replacement: arguments.drop(1), line: number }
      when 'SYNON'
        script[:groups][arguments.first] = { members: arguments.to_set, line: number }
      when 'KEY'
        current_keyword = { word: arguments.first, rank: arguments.last.to_i, line: number,
                            text: line, memory: [], decomp: [] }
        script[:keywords][arguments.first] = current_keyword
      when 'DECOMP', 'MEMORY'
        kind = name.downcase
        rules = current_keyword[kind.to_sym]
        current_rule = { kind: kind, number: rules.length + 1, pattern: arguments,
                         line: number, text: line, items: [] }
        rules << current_rule
      when 'REASM', 'GOTO', 'NEWKEY', 'RESTATE'
        current_rule[:items] << { kind: name, line: number, text: line, template: text,
                                  arguments: arguments, number: current_rule[:items].length + 1 }
      end
    end
    script
  end
end
