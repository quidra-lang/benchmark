require 'set'
require_relative 'script_loader'
require_relative 'linter'
require_relative 'matcher'
require_relative 'responder'
require_relative 'memory'

class Eliza
  SOURCES = %w[keyword memory question default repeat].freeze
  NO_ARGUMENTS = %w[:keys :why :history :memory :forget :reset :unused :stats :undo].freeze
  TEXT_ARGUMENT = %w[:prepare :reflect :say :explain].freeze
  ONE_ARGUMENT = %w[:groups :find :script :cycles :coverage].freeze
  KEYWORD_ARGUMENT = %w[:script :cycles :coverage :test].freeze
  COMMANDS = (NO_ARGUMENTS + TEXT_ARGUMENT + ONE_ARGUMENT + %w[:trace :test]).freeze

  def initialize(script)
    @script = script
    @keywords = script[:keywords]
    @rules = @keywords.values.flat_map { |keyword| keyword[:memory] + keyword[:decomp] }
    @transcript = []
    @state = { cycles: Hash.new(0), list_cycles: Hash.new(0), keyword_uses: Hash.new(0),
               keyword_replies: Hash.new(0), rule_hits: Hash.new(0), item_uses: Hash.new(0),
               memory: Memory.new(script[:capacity]), session: nil, sessions: 0,
               total_turns: 0, total_sources: SOURCES.to_h { |source| [source, 0] } }
  end

  def session
    @state[:session]
  end

  def memory
    @state[:memory]
  end

  def copy_state
    Marshal.load(Marshal.dump(@state))
  end

  def normalize(text)
    text.tr('A-Z', 'a-z').split(/[,.?!;]/).filter_map do |part|
      words = part.gsub(/[^a-z0-9']/, ' ').split(' ').filter_map do |word|
        cleaned = word.sub(/\A'+/, '').sub(/'+\z/, '')
        cleaned unless cleaned.empty?
      end
      words unless words.empty?
    end
  end

  def prepare(text)
    normalize(text).map do |clause|
      clause.flat_map { |word| @script[:pre].key?(word) ? @script[:pre][word][:replacement] : [word] }
    end
  end

  def quit?(text)
    words = normalize(text).flatten
    words.length == 1 && @script[:quit].include?(words.first)
  end

  def select_clause(clauses)
    clauses.each_with_index do |clause, index|
      positions = {}
      clause.each_with_index do |word, position|
        positions[word] = position if @keywords.key?(word) && !positions.key?(word)
      end
      next if positions.empty?

      keys = positions.keys.sort_by { |word| [-@keywords[word][:rank], positions[word]] }
      return [index + 1, clause, keys]
    end
    nil
  end

  def reset_cycles
    @rules.each { |rule| @state[:cycles][rule[:line]] = 0 }
    %w[DEFAULT QUESTION REPEAT].each { |name| @state[:list_cycles][name] = 0 }
  end

  def take_item(rule)
    index = @state[:cycles][rule[:line]]
    item = rule[:items][index]
    @state[:item_uses][item[:line]] += 1
    @state[:cycles][rule[:line]] = (index + 1) % rule[:items].length
    item
  end

  def take_text(name)
    texts = @script[:lists][name]
    index = @state[:list_cycles][name]
    @state[:list_cycles][name] = (index + 1) % texts.length
    texts[index]
  end

  def apply_memory(word, words, trace)
    @keywords[word][:memory].each do |rule|
      bindings = Matcher.match(rule[:pattern], words, @script[:groups])
      next if bindings.nil?

      trace << "MEMORY #{word} #{rule[:number]}"
      @state[:rule_hits][rule[:line]] += 1
      unless rule[:items].empty?
        item = take_item(rule)
        text = Responder.build(item[:template], bindings, @script[:post])
        memory.store(session, word, text)
      end
      break
    end
  end

  def keyword_reply(clauses, trace)
    selected = select_clause(clauses)
    unless selected
      trace << 'CLAUSE none'
      return nil
    end
    number, words, keys = selected
    trace << "CLAUSE #{number} #{words.join(' ')}"
    trace << "KEYS #{keys.join(' ')}"
    apply_memory(keys.first, words, trace)
    entered = Set.new
    keys.each do |initial|
      next if entered.include?(initial)

      trace << "ENTER #{initial}"
      current = initial
      current_words = words
      loop do
        entered.add(current)
        @state[:keyword_uses][current] += 1
        bindings = nil
        rule = @keywords[current][:decomp].find do |candidate|
          bindings = Matcher.match(candidate[:pattern], current_words, @script[:groups])
          !bindings.nil?
        end
        unless rule
          trace << "NOMATCH #{current}"
          break
        end
        @state[:rule_hits][rule[:line]] += 1
        if rule[:items].empty?
          trace << "DECOMP #{current} #{rule[:number]} 0"
          break
        end
        item = take_item(rule)
        trace << "DECOMP #{current} #{rule[:number]} #{item[:number]}"
        case item[:kind]
        when 'REASM'
          reply = Responder.build(item[:template], bindings, @script[:post])
          @state[:keyword_replies][current] += 1
          session[:topics][current] += 1
          return reply
        when 'NEWKEY'
          break
        when 'GOTO', 'RESTATE'
          target = item[:arguments].first
          if !@keywords.key?(target) || entered.include?(target)
            trace << "BLOCKED #{target}"
            break
          end
          if item[:kind] == 'RESTATE'
            current_words = Responder.restate(item[:arguments], bindings)
            trace << (["RESTATE #{target}"] + current_words).join(' ')
          else
            trace << "GOTO #{target}"
          end
          current = target
        end
      end
    end
    nil
  end

  def decide(text)
    clauses = normalize(text)
    trace = []
    if !@script[:lists]['REPEAT'].empty? && !clauses.empty? && clauses == session[:previous]
      trace << 'REPEAT'
      reply = take_text('REPEAT')
      source = 'repeat'
    else
      reply = keyword_reply(prepare(text), trace)
      if !reply.nil?
        source = 'keyword'
      elsif !memory.queue.empty?
        reply = memory.recall(session)
        source = 'memory'
      elsif text.end_with?('?') && !@script[:lists]['QUESTION'].empty?
        reply = take_text('QUESTION')
        source = 'question'
      else
        reply = take_text('DEFAULT')
        source = 'default'
      end
    end
    trace << "REPLY #{source}"
    session[:previous] = clauses
    session[:sources][source] += 1
    session[:unrecognized] << session[:turns] if %w[question default].include?(source)
    [reply, trace]
  end

  def counts_line
    "turns=#{session[:turns]} " + SOURCES.map { |source| "#{source}=#{session[:sources][source]}" }.join(' ')
  end

  def leading_counts(counts)
    values = counts.select { |_, count| count.positive? }.sort_by { |word, count| [-count, word] }.first(5)
    values.empty? ? 'none' : values.map { |word, count| "#{word} #{count}" }.join(', ')
  end

  def start_session(name)
    @transcript << '' if @state[:sessions].positive?
    reset_cycles unless @script[:persist].include?('cycles')
    memory.clear(name, 0) unless @script[:persist].include?('memory')
    @state[:sessions] += 1
    @state[:session] = { name: name, turns: 0, sources: SOURCES.to_h { |source| [source, 0] },
                        previous: nil, history: [], last_trace: nil, trace_on: false,
                        topics: Hash.new(0), words: Hash.new(0), stores: 0, recalls: 0,
                        unrecognized: [], undo: nil }
    @transcript << "SESSION #{name}"
    greetings = @script[:lists]['INITIAL']
    @transcript.concat(Responder.wrap(greetings[(@state[:sessions] - 1) % greetings.length]))
  end

  def finish_session
    unknown = session[:unrecognized].empty? ? 'none' : session[:unrecognized].join(' ')
    @transcript.concat(["NOTES #{session[:name]}", "  #{counts_line}",
                        "  topics: #{leading_counts(session[:topics])}",
                        "  words: #{leading_counts(session[:words])}",
                        "  memory: stored=#{session[:stores]} recalled=#{session[:recalls]} pending=#{memory.queue.length}",
                        "  unrecognized: #{unknown}"])
    @state[:total_turns] += session[:turns]
    SOURCES.each { |source| @state[:total_sources][source] += session[:sources][source] }
  end

  def utterance(text)
    @transcript << "YOU: #{text}"
    if quit?(text)
      greetings = @script[:lists]['FINAL']
      @transcript.concat(Responder.wrap(greetings[(@state[:sessions] - 1) % greetings.length]))
      finish_session
      return
    end
    snapshot = copy_state
    snapshot[:session][:undo] = nil
    session[:undo] = snapshot
    session[:turns] += 1
    normalize(text).flatten.each { |word| session[:words][word] += 1 unless @script[:stop].include?(word) }
    session[:history] << "#{session[:turns]}: #{text}"
    reply, trace = decide(text)
    @transcript.concat(Responder.wrap(reply))
    session[:last_trace] = trace
    @transcript.concat(trace.map { |line| "  #{line}" }) if session[:trace_on]
  end

  def prepare_command(text)
    clauses = prepare(text)
    lines = clauses.each_with_index.map { |clause, index| "clause #{index + 1}: #{clause.join(' ')}" }
    lines << 'no words' if clauses.empty?
    selected = select_clause(clauses)
    if selected
      number, _, keys = selected
      lines << "selected #{number}"
      lines << 'keys ' + keys.map { |word| "#{word}/#{@keywords[word][:rank]}" }.join(' ')
    else
      lines << 'selected none'
    end
    lines
  end

  def keyword_rules(word)
    @keywords[word][:memory] + @keywords[word][:decomp]
  end

  def test_command(word, text)
    words = prepare(text).flatten
    lines = keyword_rules(word).map do |rule|
      bindings = Matcher.match(rule[:pattern], words, @script[:groups])
      result = if bindings.nil?
                 'no match'
               elsif bindings.empty?
                 'match'
               else
                 bindings.map { |binding| "[#{binding.join(' ')}]" }.join(' ')
               end
      "#{rule[:kind]} #{rule[:number]}: #{result}"
    end
    lines.empty? ? ['no rules'] : lines
  end

  def find_command(word)
    lines = []
    lines << "keyword rank #{@keywords[word][:rank]}" if @keywords.key?(word)
    %i[pre post].each do |kind|
      @script[kind].sort_by { |_, entry| entry[:line] }.each do |source, entry|
        if source == word || entry[:replacement].include?(word)
          lines << "#{kind} #{entry[:line]}: #{source} -> #{entry[:replacement].join(' ')}"
        end
      end
    end
    @script[:groups].sort_by { |_, group| group[:line] }.each do |name, group|
      lines << "group #{name} line #{group[:line]}" if group[:members].include?(word)
    end
    @keywords.each_key do |keyword|
      keyword_rules(keyword).each do |rule|
        lines << "pattern #{keyword} #{rule[:kind]} #{rule[:number]}" if rule[:pattern].include?(word)
      end
    end
    lines << 'stop word' if @script[:stop].include?(word)
    lines << 'quit word' if @script[:quit].include?(word)
    lines.empty? ? ['not found'] : lines
  end

  def script_command(word)
    keyword = @keywords[word]
    entries = [keyword]
    keyword_rules(word).each { |rule| entries << rule; entries.concat(rule[:items]) }
    entries.sort_by { |entry| entry[:line] }.map { |entry| "#{entry[:line]} #{entry[:text]}" }
  end

  def rule_command(name, word)
    lines = keyword_rules(word).map do |rule|
      prefix = "#{rule[:kind]} #{rule[:number]}: "
      if name == ':cycles'
        status = rule[:items].empty? ? 'empty' : "next #{@state[:cycles][rule[:line]] + 1}/#{rule[:items].length}"
        prefix + status
      else
        uses = rule[:items].map { |item| @state[:item_uses][item[:line]] }
        "#{prefix}hits #{@state[:rule_hits][rule[:line]]} entries #{uses.empty? ? '-' : uses.join(' ')}"
      end
    end
    lines.empty? ? ['no rules'] : lines
  end

  def simulate_command(name, text)
    return ['would quit'] if quit?(text)

    saved = copy_state
    begin
      reply, trace = decide(text)
    ensure
      @state = saved
    end
    name == ':say' ? [reply] : trace
  end

  def command(line)
    name, _, argument_string = line.partition(' ')
    arguments = argument_string.split(' ')
    return ["unknown command #{name}"] unless COMMANDS.include?(name)

    bad = NO_ARGUMENTS.include?(name) && !arguments.empty?
    bad ||= TEXT_ARGUMENT.include?(name) && argument_string.empty?
    bad ||= ONE_ARGUMENT.include?(name) && arguments.length != 1
    bad ||= name == ':trace' && !(arguments.length == 1 && %w[on off].include?(arguments.first))
    bad ||= name == ':test' && arguments.length < 2
    return ['bad arguments'] if bad
    if KEYWORD_ARGUMENT.include?(name) && !@keywords.key?(arguments.first)
      return ["unknown keyword #{arguments.first}"]
    end

    case name
    when ':prepare'
      prepare_command(argument_string)
    when ':test'
      test_command(arguments.first, argument_string.partition(' ')[2])
    when ':reflect'
      lines = prepare(argument_string).map { |clause| Responder.reflect(clause, @script[:post]).join(' ') }
      lines.empty? ? ['no words'] : lines
    when ':keys'
      @keywords.values.sort_by { |keyword| [-keyword[:rank], keyword[:word]] }
               .map { |keyword| "#{keyword[:word]}/#{keyword[:rank]}" }.each_slice(8).map { |slice| slice.join(' ') }
    when ':groups'
      names = @script[:groups].select { |_, group| group[:members].include?(arguments.first) }.keys.sort
      [names.empty? ? 'none' : names.join(' ')]
    when ':find'
      find_command(arguments.first)
    when ':script'
      script_command(arguments.first)
    when ':why'
      session[:last_trace].nil? ? ['no reply yet'] : session[:last_trace]
    when ':trace'
      session[:trace_on] = arguments.first == 'on'
      ["trace #{arguments.first}"]
    when ':history'
      session[:history].empty? ? ['no turns yet'] : session[:history].last(5)
    when ':memory'
      ["memory #{memory.queue.length}/#{memory.capacity}"] + memory.queue.each_with_index.map { |text, index| "#{index + 1}: #{text}" }
    when ':forget'
      ["forgot #{memory.clear(session[:name], session[:turns])}"]
    when ':cycles', ':coverage'
      rule_command(name, arguments.first)
    when ':reset'
      reset_cycles
      ['cycles reset']
    when ':unused'
      numbers = @rules.flat_map { |rule| rule[:items] }.select { |item| @state[:item_uses][item[:line]].zero? }
                      .map { |item| item[:line] }.sort
      ["unused #{numbers.length}"] + numbers.each_slice(12).map { |slice| slice.join(' ') }
    when ':stats'
      [counts_line]
    when ':say', ':explain'
      simulate_command(name, argument_string)
    when ':undo'
      if session[:undo].nil?
        ['nothing to undo']
      else
        @state = session[:undo]
        ["undone turn #{session[:turns] + 1}"]
      end
    end
  end

  def keyword_statistics
    lines = ['keyword,rank,uses,replies,decomposition_hits']
    @keywords.values.sort_by { |keyword| [-@state[:keyword_uses][keyword[:word]], keyword[:word]] }.each do |keyword|
      word = keyword[:word]
      hits = keyword[:decomp].map { |rule| @state[:rule_hits][rule[:line]] }
      lines << [word, keyword[:rank], @state[:keyword_uses][word], @state[:keyword_replies][word],
                hits.empty? ? '-' : hits.join('/')].join(',')
    end
    lines
  end

  def run(path)
    File.foreach(path, chomp: true) do |line|
      if line.start_with?('SESSION ')
        start_session(line.delete_prefix('SESSION '))
      elsif line.start_with?(':')
        @transcript << line
        @transcript.concat(command(line).map { |output| "  #{output}" })
      else
        utterance(line)
      end
    end
    summary = "SUMMARY sessions=#{@state[:sessions]} turns=#{@state[:total_turns]} " +
              SOURCES.map { |source| "#{source}=#{@state[:total_sources][source]}" }.join(' ')
    @transcript.concat(['', summary])
    { 'transcript.txt' => @transcript, 'keyword_stats.csv' => keyword_statistics, 'memory_log.txt' => memory.log }
  end
end

script = ScriptLoader.load('input/script.txt')
Dir.mkdir('output') unless Dir.exist?('output')
File.write('output/lint.txt', Linter.check(script).join("\n") + "\n")
Eliza.new(script).run('input/dialogue.txt').each do |name, lines|
  File.write("output/#{name}", lines.empty? ? '' : lines.join("\n") + "\n")
end
