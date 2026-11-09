require 'set'
require_relative 'reader'
require_relative 'database'
require_relative 'predicates'

module Prolog
  Entry = Struct.new(:goal, :barrier, :context)
  Marker = Struct.new(:kind, :value)
  ChoicePoint = Struct.new(:kind, :trail, :resume, :data)
  class InferenceLimit < StandardError; end
  class RaisedBall < StandardError
    attr_reader :ball
    def initialize(ball)
      @ball = Terms.copy(ball)
      super('Prolog exception')
    end
  end
  class Interpreter
    CONTROLS = [[',', 2], ['!', 0], [';', 2], ['->', 2], ['\\+', 1], ['catch', 3]] + (1..8).map { |n| ['call', n] }
    def initialize
      @database = Database.new
      @reports = []
      @file_counts = Hash.new { |h, k| h[k] = { clauses: 0, errors: 0, warnings: 0 } }
      @calls, @tries = Hash.new(0), Hash.new(0)
    end
    def reserved?(key) = CONTROLS.include?(key) || Predicates::SIGNATURES.include?(key)
    def shape?(term, name, arity) = term.is_a?(Compound) && term.name == name && term.args.length == arity
    def convert(term)
      term = Terms.deref(term)
      return Terms.compound('call', term) if term.is_a?(Variable)
      return nil if term.is_a?(Integer)
      if term.is_a?(Compound) && %w[, ; ->].include?(term.name) && term.args.length == 2
        left, right = term.args.map { |a| convert(a) }
        return nil unless left && right
        Terms.compound(term.name, left, right)
      else
        term
      end
    end
    def atom_name(name, quoted)
      return name unless quoted
      simple = name.match?(/\A[a-z][A-Za-z0-9_]*\z/) || !name.empty? && name != '.' && name.chars.all? { |c| SYMBOLS.include?(c) } || %w[[] ! ;].include?(name)
      return name if simple
      escaped = name.each_char.map { |c| { '\\' => '\\\\', "'" => "\\'", "\n" => '\\n', "\t" => '\\t' }.fetch(c, c) }.join
      "'#{escaped}'"
    end
    def writer_names(seed = {})
      count = 0
      lambda { |variable| seed[variable] ||= "_G#{count += 1}" }
    end
    def write_term(term, quoted = true, limit = 1200, operand = false, names = nil)
      names ||= writer_names
      term = Terms.deref(term)
      case term
      when Variable then names.call(term)
      when Integer then term.to_s
      when String
        result = atom_name(term, quoted)
        operand && (INFIX.key?(term) || PREFIX.key?(term)) ? "(#{result})" : result
      when Compound
        name, args = term.name, term.args
        if name == '.' && args.length == 2
          elements, tail = Terms.elements(term)
          text = elements.map { |a| write_term(a, quoted, 999, false, names) }.join(',')
          text += "|#{write_term(tail, quoted, 999, false, names)}" unless tail == '[]'
          "[#{text}]"
        elsif args.length == 2 && INFIX.key?(name)
          p, type = INFIX[name]
          l = write_term(args[0], quoted, type == :yfx ? p : p - 1, true, names)
          r = write_term(args[1], quoted, type == :xfy ? p : p - 1, true, names)
          if name == ','
            text = "#{l},#{r}"
          elsif name.match?(/\A[a-z]/)
            text = "#{l} #{name} #{r}"
          else
            before = !l.empty? && SYMBOLS.include?(l[-1]) ? ' ' : ''
            after = !r.empty? && SYMBOLS.include?(r[0]) ? ' ' : ''
            text = "#{l}#{before}#{name}#{after}#{r}"
          end
          p > limit ? "(#{text})" : text
        elsif args.length == 1 && PREFIX.key?(name)
          p = PREFIX[name]
          x = write_term(args[0], quoted, p, true, names)
          space = !x.empty? && (SYMBOLS.include?(x[0]) || x[0].match?(/[0-9(]/)) ? ' ' : ''
          text = "#{name}#{space}#{x}"
          p > limit ? "(#{text})" : text
        else
          "#{atom_name(name, quoted)}(#{args.map { |a| write_term(a, quoted, 999, false, names) }.join(',')})"
        end
      end
    end
    def indicator_text(key) = write_term(Terms.pi(*key))
    def report(file, line, kind, message)
      @reports << "#{file}:#{line}: #{kind}: #{message}"
      @file_counts[file][kind == 'error' ? :errors : :warnings] += 1
    end
    def consult(file)
      text = File.read("input/#{file}")
      lines, reader, last, warned = text.lines(chomp: true), Reader.new(text), nil, Set.new
      until reader.peek.kind == :eof
        line = reader.peek.line
        begin
          term = reader.clause
        rescue ReadError => e
          token = e.token
          @reports << "#{file}:#{token.line}:#{token.column}: syntax error: #{e.message}"
          unless token.kind == :eof
            @reports << "    #{lines.fetch(token.line - 1)}"
            @reports << "#{' ' * (token.column + 3)}^"
          end
          @file_counts[file][:errors] += 1
          reader.recover(e)
          next
        end
        head, body = shape?(term, ':-', 2) ? term.args : [term, nil]
        error = if head.is_a?(Variable)
                  'instantiation_error'
                elsif head.is_a?(Integer)
                  Terms.error('type_error', 'callable', head)
                elsif reserved?(Terms.indicator(head))
                  Terms.error('permission_error', 'modify', 'static_procedure', Terms.pi(*Terms.indicator(head)))
                elsif body && !convert(body)
                  Terms.error('type_error', 'callable', body)
                end
        if error
          report(file, line, 'error', write_term(error))
          next
        end
        body = convert(body) if body
        key = Terms.indicator(head)
        previous = @database.predicates[key]
        if file == 'program.pl' && previous && previous.any? { |c| c.file == 'prelude.pl' }
          report(file, line, 'warning', "redefining prelude procedure #{indicator_text(key)}")
          previous.clear
        end
        if previous && previous.any? { |c| c.file == file } && last != key && !warned.include?(key)
          report(file, line, 'warning', "clauses of #{indicator_text(key)} are not together")
          warned << key
        end
        @database.add(key, Clause.new(head: head, body: body, file: file, line: line))
        @file_counts[file][:clauses] += 1
        last = key
        singles = reader.occurrences.select { |name, count| !name.start_with?('_') && count == 1 }.keys
        repeats = reader.occurrences.select { |name, count| name.start_with?('_') && name.length >= 2 && count >= 2 }.keys
        report(file, line, 'warning', "singleton variables: #{singles.join(', ')}") unless singles.empty?
        report(file, line, 'warning', "variables starting with _ occur more than once: #{repeats.join(', ')}") unless repeats.empty?
      end
    end
    def undefined_warnings
      warned = Set.new
      traverse = lambda do |term, clause, parent|
        return unless Terms.callable?(term)
        key = Terms.indicator(term)
        if %w[, ; ->].include?(key[0]) && key[1] == 2
          term.args.each { |a| traverse.call(a, clause, parent) }
        elsif key == ['\\+', 1] || key == ['call', 1]
          traverse.call(term.args[0], clause, parent)
        elsif key == ['findall', 3]
          traverse.call(term.args[1], clause, parent)
        elsif key == ['catch', 3]
          traverse.call(term.args[0], clause, parent)
          traverse.call(term.args[2], clause, parent)
        elsif !reserved?(key) && !@database.predicates.key?(key) && warned.add?(key)
          report(clause.file, clause.line, 'warning', "undefined procedure #{indicator_text(key)} called from #{indicator_text(parent)}")
        end
      end
      @database.predicates.each { |key, clauses| clauses.each { |c| traverse.call(c.body, c, key) if c.body } }
    end
    def listing
      groups = @database.predicates.values.map do |clauses|
        clauses.flat_map do |clause|
          occurrences = Terms.variables(clause.head)
          Terms.variables(clause.body, occurrences) if clause.body
          counts, seed, index = occurrences.tally, {}, 0
          counts.each do |variable, count|
            if count == 1
              seed[variable] = '_'
            else
              seed[variable] = (65 + index % 26).chr + (index < 26 ? '' : (index / 26).to_s)
              index += 1
            end
          end
          names = ->(v) { seed.fetch(v) }
          head = write_term(clause.head, true, 1200, false, names)
          next ["#{head}."] unless clause.body
          goals, body = [], clause.body
          while shape?(body, ',', 2)
            goals << body.args[0]
            body = body.args[1]
          end
          goals << body
          ["#{head} :-", *goals.each_with_index.map { |g, i| "    #{write_term(g, true, 999, false, names)}#{i == goals.length - 1 ? '.' : ','}" }]
        end.join("\n")
      end
      groups.empty? ? '' : groups.join("\n\n") + "\n"
    end
    def push(goals, tail)
      goals.reverse_each.reduce(tail) { |list, entry| [entry, list] }
    end
    def entry(goal, barrier, context) = Entry.new(goal, barrier, context)
    def point(kind, continuation, data = {})
      cp = ChoicePoint.new(kind, @unifier.trail.length, continuation, data)
      @choices << cp
      @counters[:choicepoints] += 1
      cp
    end
    def cut(height)
      @choices.pop while @choices.length > height
    end
    def inference(key)
      raise InferenceLimit if @counters[:inferences] == 20000
      @counters[:inferences] += 1
      @calls[key] += 1
    end
    def try_clause(clause, goal, barrier, context, continuation)
      @tries[Terms.indicator(goal)] += 1
      head, body = @database.copy_clause(clause)
      return false unless @unifier.unify(head, goal)
      @goals = body ? push([entry(body, barrier, context)], continuation) : continuation
      true
    end
    def user_call(goal, barrier, context, continuation)
      key = Terms.indicator(goal)
      Terms.raise_error('existence_error', 'procedure', Terms.pi(*key)) unless @database.predicates.key?(key)
      candidates = @database.candidates(goal)
      return false if candidates.empty?
      height = @choices.length
      point(:clauses, continuation, goal: goal, candidates: candidates, next: 1, barrier: height, context: context) if candidates.length >= 2
      try_clause(candidates.first, goal, height, context, continuation)
    end
    def between(args, continuation, context)
      low, high = @predicates.integer(args[0]), @predicates.integer(args[1])
      x = Terms.deref(args[2])
      Terms.raise_error('type_error', 'integer', x) unless x.is_a?(Variable) || x.is_a?(Integer)
      return (low..high).cover?(x) if x.is_a?(Integer)
      return false if low > high
      point(:between, continuation, high: high, variable: x, next: low + 1, context: context) if low < high
      @unifier.unify(x, low)
    end
    def length(args, continuation, context)
      n = Terms.deref(args[1])
      Terms.raise_error('type_error', 'integer', n) unless n.is_a?(Variable) || n.is_a?(Integer)
      Terms.raise_error('domain_error', 'not_less_than_zero', n) if n.is_a?(Integer) && n.negative?
      elements, tail = Terms.elements(args[0])
      count = elements.length
      return @unifier.unify(n, count) if tail == '[]'
      Terms.raise_error('type_error', 'list', args[0]) unless tail.is_a?(Variable)
      if n.is_a?(Integer)
        return false if n < count
        @unifier.unify(tail, Terms.list(Array.new(n - count) { Variable.new }))
      else
        point(:length, continuation, tail: tail, variable: n, count: count, next: count + 1, context: context)
        @unifier.unify(tail, '[]') && @unifier.unify(n, count)
      end
    end
    def execute(entry_value, continuation)
      goal, c, k = entry_value.goal, entry_value.barrier, entry_value.context
      @goals = continuation
      if goal.is_a?(Marker)
        case goal.kind
        when :ite then cut(goal.value)
        when :naf then cut(goal.value); return false
        when :exit then @choices.pop if @choices.last.equal?(goal.value)
        when :collect then goal.value.data[:results] << Terms.copy(goal.value.data[:template]); return false
        end
        return true
      end
      goal = Terms.deref(goal)
      key = Terms.indicator(goal)
      args = goal.is_a?(Compound) ? goal.args : []
      if key == [',', 2]
        @goals = push(args.map { |g| entry(g, c, k) }, continuation)
      elsif key == ['!', 0]
        cut(c)
      elsif key == [';', 2]
        height = @choices.length
        point(:alt, push([entry(args[1], c, k)], continuation))
        if shape?(args[0], '->', 2)
          i, t = args[0].args
          @goals = push([entry(i, height + 1, k), entry(Marker.new(:ite, height), c, k), entry(t, c, k)], continuation)
        else
          @goals = push([entry(args[0], c, k)], continuation)
        end
      elsif key == ['->', 2]
        height = @choices.length
        @goals = push([entry(args[0], height, k), entry(Marker.new(:ite, height), c, k), entry(args[1], c, k)], continuation)
      elsif key == ['\\+', 1]
        height = @choices.length
        point(:alt, continuation)
        @goals = push([entry(Terms.compound('call', args[0]), c, k), entry(Marker.new(:naf, height), c, k)], continuation)
      elsif key[0] == 'call' && (1..8).cover?(key[1])
        target = Terms.deref(args[0])
        Terms.raise_error('instantiation_error') if target.is_a?(Variable)
        Terms.raise_error('type_error', 'callable', target) if target.is_a?(Integer)
        if args.length > 1
          target = target.is_a?(String) ? Compound.new(target, args.drop(1)) : Compound.new(target.name, target.args + args.drop(1))
        end
        converted = convert(target)
        Terms.raise_error('type_error', 'callable', target) unless converted
        @goals = push([entry(converted, @choices.length, k)], continuation)
      elsif key == ['catch', 3]
        cp = point(:catch, continuation, catcher: args[1], recovery: args[2], parent: k)
        @goals = push([entry(Terms.compound('call', args[0]), c, cp), entry(Marker.new(:exit, cp), c, k)], continuation)
      else
        inference(key)
        case key
        when ['findall', 3]
          cp = point(:findall, continuation, template: args[0], result: args[2], results: [])
          @goals = push([entry(Terms.compound('call', args[1]), c, k), entry(Marker.new(:collect, cp), c, k)], nil)
        when ['throw', 1]
          ball = Terms.deref(args[0])
          Terms.raise_error('instantiation_error') if ball.is_a?(Variable)
          raise RaisedBall.new(ball)
        when ['between', 3] then return between(args, continuation, k)
        when ['length', 2] then return length(args, continuation, k)
        else
          return @predicates.execute(goal) if Predicates::SIGNATURES.include?(key)
          return user_call(goal, c, k, continuation)
        end
      end
      true
    rescue LogicError => error
      raise RaisedBall.new(Terms.compound('error', error.term, Terms.pi(*key)))
    end
    def backtrack
      loop do
        @counters[:backtracks] += 1
        loop do
          return false if @choices.empty?
          cp = @choices.last
          @unifier.undo(cp.trail)
          if cp.kind == :catch
            @choices.pop
            next
          end
          break
        end
        cp, data = @choices.last, @choices.last.data
        case cp.kind
        when :alt
          @choices.pop
          @goals = cp.resume
          return true
        when :clauses
          index = data[:next]
          index == data[:candidates].length - 1 ? @choices.pop : data[:next] += 1
          return true if try_clause(data[:candidates][index], data[:goal], data[:barrier], data[:context], cp.resume)
        when :between
          inference(['between', 3])
          value = data[:next]
          value == data[:high] ? @choices.pop : data[:next] += 1
          if @unifier.unify(data[:variable], value)
            @goals = cp.resume
            return true
          end
        when :length
          inference(['length', 2])
          size = data[:next]
          data[:next] += 1
          if @unifier.unify(data[:tail], Terms.list(Array.new(size - data[:count]) { Variable.new })) && @unifier.unify(data[:variable], size)
            @goals = cp.resume
            return true
          end
        when :findall
          @choices.pop
          if @unifier.unify(Terms.list(data[:results]), data[:result])
            @goals = cp.resume
            return true
          end
        end
      end
    end
    def handle_exception(ball, context)
      while context
        index = @choices.index { |cp| cp.equal?(context) }
        cut(index)
        @unifier.undo(context.trail)
        height = @unifier.trail.length
        if @unifier.unify(Terms.copy(ball), context.data[:catcher])
          @goals = push([entry(Terms.compound('call', context.data[:recovery]), @choices.length, context.data[:parent])], context.resume)
          return true
        end
        @unifier.undo(height)
        context = context.data[:parent]
      end
      @answer_lines << "uncaught exception: #{write_term(ball)}"
      false
    end
    def answer(variables)
      seed = {}
      variables.each do |name, variable|
        value = Terms.deref(variable)
        seed[value] ||= name if value.is_a?(Variable)
      end
      names, previous, items = writer_names(seed), {}, []
      variables.each do |name, variable|
        value = Terms.deref(variable)
        if value.is_a?(Variable)
          items << "#{previous[value]} = #{name}" if previous.key?(value)
          previous[value] = name
        else
          items << "#{name} = #{write_term(value, true, 699, true, names)}"
        end
      end
      items.empty? ? 'true' : items.join(', ')
    end
    def query(term, variables, limit)
      @unifier, @choices, @query_output, @answer_lines = Unifier.new, [], +'', []
      @counters = { solutions: 0, inferences: 0, choicepoints: 0, backtracks: 0 }
      @predicates = Predicates.new(@unifier, @query_output, ->(t, q) { write_term(t, q) })
      @goals = push([entry(Terms.compound('call', term), 0, nil)], nil)
      loop do
        begin
          if @goals.nil?
            @counters[:solutions] += 1
            done = @counters[:solutions] == limit || @choices.empty?
            @answer_lines << answer(variables) + (done ? '.' : ' ;')
            break if done
            unless backtrack
              @answer_lines << 'false.'
              break
            end
          else
            current, continuation = @goals
            begin
              success = execute(current, continuation)
            rescue RaisedBall => error
              break unless handle_exception(error.ball, current.context)
              next
            end
            unless success || backtrack
              @answer_lines << 'false.'
              break
            end
          end
        rescue InferenceLimit
          @answer_lines << 'inference limit exceeded'
          break
        end
      end
      [@answer_lines, @query_output, @counters]
    end
    def counters_text(counts) = counts.map { |name, n| "#{name}=#{n}" }.join(' ')
    def run
      %w[prelude.pl program.pl].each { |file| consult(file) }
      undefined_warnings
      %w[prelude.pl program.pl].each do |file|
        @reports << "#{file}: #{counters_text(@file_counts[file])}"
      end
      @reports << "database: predicates=#{@database.predicates.length} clauses=#{@database.predicates.values.sum(&:length)}"
      answers, writes, stats = [], +'', []
      totals = { solutions: 0, inferences: 0, choicepoints: 0, backtracks: 0 }
      File.readlines('input/queries.txt', chomp: true).each_with_index do |line, i|
        number = i + 1
        answers << line
        writes << "== query #{number} ==\n"
        prefix = /\A(?:(\d+) )?\?- /.match(line)
        reader = Reader.new(line[prefix.end(0)..], prefix.end(0) + 1)
        begin
          term = reader.clause(query: true)
        rescue ReadError => e
          answers << "syntax error at column #{e.token.column}: #{e.message}"
          stats << "query #{number}: syntax error"
          next
        end
        variables = reader.variables.reject { |name, _| name.start_with?('_') }
        lines, output, counts = query(term, variables, prefix[1]&.to_i)
        answers.concat(lines)
        writes << output
        writes << "\n" unless output.empty? || output.end_with?("\n")
        stats << "query #{number}: #{counters_text(counts)}"
        counts.each { |key, count| totals[key] += count }
      end
      stats << "total: #{counters_text(totals)}"
      stats << '== profile =='
      @calls.keys.sort_by { |key| [-@calls[key], indicator_text(key)] }.each do |key|
        text = "#{indicator_text(key)} calls=#{@calls[key]}"
        text += " tries=#{@tries[key]}" if @database.predicates.key?(key)
        stats << text
      end
      File.write('output/consult.txt', @reports.join("\n") + "\n")
      File.write('output/listing.txt', listing)
      File.write('output/answers.txt', answers.empty? ? '' : answers.join("\n") + "\n")
      File.write('output/write_output.txt', writes)
      File.write('output/stats.txt', stats.join("\n") + "\n")
    end
  end
end

Prolog::Interpreter.new.run if $PROGRAM_NAME == __FILE__
