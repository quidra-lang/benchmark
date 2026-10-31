# frozen_string_literal: true

require_relative 'scoring'
require_relative 'substitution'
require_relative 'transposition'
require_relative 'playfair'
require_relative 'analysis'

class CipherTool
  COMMANDS = %w[ENCRYPT DECRYPT BREAK ANALYZE COMPARE IDENTIFY].freeze
  CIPHERS = %w[caesar affine vigenere autokey playfair railfence columnar].freeze
  SUBSTITUTION = %w[caesar affine vigenere autokey].freeze
  Message = Struct.new(:lines, :text, :letters, keyword_init: true)
  Job = Struct.new(:number, :command, :cipher, :key, :source, :other, :new_name, :options, keyword_init: true)
  Candidate = Struct.new(:key, :plaintext, :score, :order, keyword_init: true)
  BreakResult = Struct.new(:candidates, :key, :plaintext, :score, :periods, :examination,
                           :length, :method, :passes, :changes, keyword_init: true)
  class JobError < StandardError; end

  def initialize
    @weights = Scoring::Weights.new(read_lines('input/weights.txt'))
    @messages = {}
    read_messages
    @results = []
    @candidates = []
    @analysis = []
    @totals = COMMANDS.to_h { |command| [command, {ok: 0, errors: 0}] }
    @jobs = 0
    @ok = 0
    @errors = 0
  end

  def read_lines(path)
    File.binread(path).lines(chomp: true)
  end

  def add_message(name, lines)
    text = lines.join("\n")
    @messages[name] = Message.new(lines: lines.dup, text: text, letters: Scoring.letters(text))
  end

  def read_messages
    lines = read_lines('input/messages.txt')
    index = 0
    while index < lines.length
      if lines[index].empty?
        index += 1
        next
      end
      name = lines[index].delete_prefix('MESSAGE ')
      index += 1
      body = []
      until lines[index] == 'END'
        body << lines[index]
        index += 1
      end
      add_message(name, body)
      index += 1
    end
  end

  def valid_name?(name)
    /\A[a-z0-9_]{1,16}\z/.match?(name)
  end

  def valid_key?(cipher, key)
    case cipher
    when 'caesar'
      /\A[0-9]{1,2}\z/.match?(key) && key.to_i.between?(0, 25)
    when 'affine'
      return false unless /\A[0-9]{1,2},[0-9]{1,2}\z/.match?(key)

      multiplier, offset = key.split(',').map(&:to_i)
      Substitution::AFFINE_MULTIPLIERS.include?(multiplier) && offset.between?(0, 25)
    when 'vigenere', 'autokey'
      /\A[A-Za-z]{1,20}\z/.match?(key)
    when 'playfair'
      /\A[A-Za-z]{1,25}\z/.match?(key)
    when 'railfence'
      /\A[0-9]{1,2}\z/.match?(key) && key.to_i.between?(2, 20)
    when 'columnar'
      /\A[A-Za-z0-9]{2,9}\z/.match?(key)
    end
  end

  def key_notation(cipher, key)
    case cipher
    when 'caesar', 'railfence' then key.to_i.to_s
    when 'affine' then key.split(',').map(&:to_i).join(',')
    when 'playfair' then key.upcase.tr('J', 'I')
    else key.upcase
    end
  end

  def option_rules(command, cipher = nil)
    return {'MAXLEN' => [2, 20, 10]} if command == 'ANALYZE'
    return {'KEYS' => nil} if command == 'IDENTIFY'

    rules = {'TOP' => [1, 20, 5]}
    case cipher
    when 'vigenere'
      rules.merge!('MAXLEN' => [2, 20, 10], 'IOC' => [1, 100_000, 6000],
                   'KASISKI' => [1, 100, 60], 'REFINE' => [0, 10, 5])
    when 'autokey' then rules['MAXLEN'] = [1, 20, 8]
    when 'railfence' then rules['MAXRAILS'] = [2, 20, 10]
    when 'columnar' then rules['MAXLEN'] = [2, 6, 6]
    when 'playfair' then rules['KEYS'] = nil
    end
    rules
  end

  def default_options(command, cipher = nil)
    option_rules(command, cipher).each_with_object({}) do |(name, rule), options|
      options[name] = rule[2] unless rule.nil?
    end
  end

  def parse_options(command, cipher, tokens)
    rules = option_rules(command, cipher)
    options = default_options(command, cipher)
    seen = {}
    tokens.each do |token|
      name, separator, value = token.partition('=')
      invalid = separator.empty? || !rules.key?(name) || seen.key?(name)
      unless invalid
        rule = rules[name]
        invalid = if name == 'KEYS'
                    !valid_name?(value)
                  else
                    !/\A[0-9]{1,6}\z/.match?(value) || !value.to_i.between?(rule[0], rule[1])
                  end
      end
      raise JobError, "bad option #{token}" if invalid

      seen[name] = true
      options[name] = name == 'KEYS' ? value : value.to_i
    end
    if command == 'BREAK' && cipher == 'playfair' && !options.key?('KEYS')
      raise JobError, 'missing option KEYS'
    end
    options
  end

  def parse_job(words)
    command = words[0]
    raise JobError, 'unknown command' unless COMMANDS.include?(command)

    new_name = nil
    if %w[ENCRYPT DECRYPT BREAK].include?(command) && words.length >= 5 && words[-2] == 'AS'
      new_name = words[-1]
      words = words[0...-2]
      raise JobError, 'bad syntax' unless valid_name?(new_name)
    end
    valid_length = case command
                   when 'ENCRYPT', 'DECRYPT' then words.length == 4
                   when 'BREAK' then words.length >= 3
                   when 'ANALYZE', 'IDENTIFY' then words.length.between?(2, 3)
                   when 'COMPARE' then words.length == 3
                   end
    raise JobError, 'bad syntax' unless valid_length

    job = Job.new(number: @jobs, command: command, new_name: new_name, options: {})
    if %w[ENCRYPT DECRYPT BREAK].include?(command)
      job.cipher = words[1]
      raise JobError, "unknown cipher #{job.cipher}" unless CIPHERS.include?(job.cipher)
    end
    case command
    when 'ENCRYPT', 'DECRYPT'
      raise JobError, "bad key #{words[2]}" unless valid_key?(job.cipher, words[2])

      job.key = key_notation(job.cipher, words[2])
      job.source = words[3]
    when 'BREAK'
      job.source = words[2]
      job.options = parse_options(command, job.cipher, words.drop(3))
    when 'ANALYZE', 'IDENTIFY'
      job.source = words[1]
      job.options = parse_options(command, nil, words.drop(2))
    when 'COMPARE'
      job.source, job.other = words[1, 2]
    end
    references = [job.source]
    references << job.other if command == 'COMPARE'
    references << job.options['KEYS'] if job.options.key?('KEYS')
    references.each do |name|
      raise JobError, "unknown message #{name}" unless @messages.key?(name)
    end
    if !new_name.nil? && @messages.key?(new_name)
      raise JobError, "duplicate message #{new_name}"
    end
    job
  end

  def transform(text, cipher, key, decrypt: false)
    return Substitution.transform(text, cipher, key, decrypt: decrypt) if SUBSTITUTION.include?(cipher)

    case cipher
    when 'railfence' then Transposition.railfence(text, key.to_i, decrypt: decrypt)
    when 'columnar' then Transposition.columnar(text, key, decrypt: decrypt)
    when 'playfair' then Playfair.transform(text, key, decrypt: decrypt)
    end
  end

  def five_letter_groups(text)
    groups = []
    index = 0
    while index < text.length
      groups << text.byteslice(index, 5)
      index += 5
    end
    groups.each_slice(10).map { |line| line.join(' ') }
  end

  def result_lines(source, cipher, key, plaintext)
    if SUBSTITUTION.include?(cipher)
      transform(source.text, cipher, key, decrypt: true).split("\n", -1)
    else
      five_letter_groups(plaintext)
    end
  end

  def publish(job, header, lines)
    header += " as=#{job.new_name}" unless job.new_name.nil?
    @results << header
    @results.concat(lines)
    add_message(job.new_name, lines) unless job.new_name.nil?
  end

  def encrypt_or_decrypt(job)
    source = @messages.fetch(job.source)
    raise JobError, 'no letters' if source.letters.empty?

    decrypt = job.command == 'DECRYPT'
    if decrypt && job.cipher == 'playfair' && !Playfair.valid_ciphertext?(source.letters)
      raise JobError, 'bad playfair text'
    end
    input = SUBSTITUTION.include?(job.cipher) ? source.text : source.letters
    output = transform(input, job.cipher, job.key, decrypt: decrypt)
    lines = SUBSTITUTION.include?(job.cipher) ? output.split("\n", -1) : five_letter_groups(output)
    header = "JOB #{job.number} #{job.command} #{job.cipher} key=#{job.key} source=#{job.source}"
    header += " letters=#{Scoring.letters(output).length} lines=#{lines.length}"
    publish(job, header, lines)
  end

  def key_list(message_name)
    @messages.fetch(message_name).text.scan(/[A-Za-z]+/).map { |word| word.upcase.tr('J', 'I') }.uniq
  end

  def column_key(text, length, cipher)
    key = String.new(encoding: Encoding::ASCII_8BIT)
    Analysis.columns(text, length).each do |column|
      best_value = 0
      best_score = nil
      26.times do |seed|
        shift = seed
        score = 0
        column.each_byte do |byte|
          plain = (byte - 65 - shift) % 26
          score += @weights.monograms[plain]
          shift = plain if cipher == 'autokey'
        end
        if best_score.nil? || score > best_score
          best_value = seed
          best_score = score
        end
      end
      key << best_value + 65
    end
    key
  end

  def add_candidate(candidates, text, cipher, key)
    plaintext = transform(text, cipher, key, decrypt: true)
    score = if %w[caesar affine].include?(cipher)
              @weights.monogram(plaintext)
            else
              @weights.bigram(plaintext)
            end
    candidates << Candidate.new(key: key, plaintext: plaintext, score: score, order: candidates.length)
  end

  def generate_candidates(text, cipher, options, keys)
    candidates = []
    case cipher
    when 'caesar'
      26.times { |key| add_candidate(candidates, text, cipher, key.to_s) }
    when 'affine'
      Substitution::AFFINE_MULTIPLIERS.each do |multiplier|
        26.times { |offset| add_candidate(candidates, text, cipher, "#{multiplier},#{offset}") }
      end
    when 'railfence'
      (2..options['MAXRAILS']).each { |key| add_candidate(candidates, text, cipher, key.to_s) }
    when 'columnar'
      (2..options['MAXLEN']).each do |length|
        (1..length).map(&:to_s).permutation.map(&:join).sort.each do |key|
          add_candidate(candidates, text, cipher, key)
        end
      end
    when 'playfair'
      keys.each { |key| add_candidate(candidates, text, cipher, key) }
    when 'vigenere', 'autokey'
      (1..options['MAXLEN']).each do |length|
        add_candidate(candidates, text, cipher, column_key(text, length, cipher))
      end
    end
    candidates.sort_by { |candidate| [-candidate.score, candidate.order] }
  end

  def vigenere_length(periods, examination, options)
    gap_count = examination[:gaps].length
    kasiski = if gap_count.positive?
                periods.drop(1).select { |row| 100 * row[:kasiski] >= options['KASISKI'] * gap_count }.last
              end
    return [kasiski[:length], 'kasiski'] if kasiski && kasiski[:ioc] >= options['IOC']

    threshold = periods.find { |row| row[:ioc] >= options['IOC'] }
    return [threshold[:length], 'ioc'] unless threshold.nil?

    maximum = periods.max_by { |row| [row[:ioc], -row[:length]] }
    [maximum[:length], 'maxioc']
  end

  def refine_vigenere(text, candidate, maximum_passes)
    key = candidate.key.dup
    score = candidate.score
    passes = 0
    changes = 0
    maximum_passes.times do
      passes += 1
      changed = false
      key.length.times do |index|
        best_score = nil
        best_letter = 65
        26.times do |value|
          trial = key.dup
          trial.setbyte(index, value + 65)
          fitness = @weights.bigram(transform(text, 'vigenere', trial, decrypt: true))
          if best_score.nil? || fitness > best_score
            best_score = fitness
            best_letter = value + 65
          end
        end
        next unless best_score > score

        key.setbyte(index, best_letter)
        score = best_score
        changes += 1
        changed = true
      end
      break unless changed
    end
    {key: key, score: score, plaintext: transform(text, 'vigenere', key, decrypt: true), passes: passes, changes: changes}
  end

  def break_cipher(text, cipher, options, keys = nil)
    candidates = generate_candidates(text, cipher, options, keys)
    best = candidates.first
    result = BreakResult.new(candidates: candidates, key: best.key, plaintext: best.plaintext, score: best.score)
    return result unless cipher == 'vigenere'

    result.examination = Analysis.kasiski(text)
    result.periods = Analysis.periods(text, options['MAXLEN'], result.examination)
    result.length, result.method = vigenere_length(result.periods, result.examination, options)
    selected = candidates.find { |candidate| candidate.key.length == result.length }
    refinement = refine_vigenere(text, selected, options['REFINE'])
    refinement.each { |name, value| result[name] = value }
    result
  end

  def period_lines(periods)
    periods.map do |row|
      "L=#{row[:length]} ioc=#{row[:ioc]} kasiski=#{row[:kasiski]} cols=#{row[:columns].join(',')}"
    end
  end

  def kasiski_lines(examination)
    lines = ["kasiski repeats=#{examination[:repeats].length} spacings=#{examination[:gaps].length}"]
    examination[:repeats].each do |row|
      lines << "#{row[:trigram]} at=#{row[:positions].join(',')} gaps=#{row[:gaps].join(',')} gcd=#{row[:gcd]}"
    end
    lines
  end

  def break_analysis(job, text, result)
    return unless %w[vigenere playfair].include?(job.cipher)

    @analysis << "JOB #{job.number} BREAK #{job.cipher} source=#{job.source}"
    @analysis << "letters=#{text.length}"
    if job.cipher == 'vigenere'
      @analysis.concat(period_lines(result.periods))
      @analysis.concat(kasiski_lines(result.examination))
      @analysis << "decision length=#{result.length} method=#{result.method}"
      @analysis << "refine passes=#{result.passes} changes=#{result.changes} key=#{result.key}"
    else
      pairs = Analysis.pair_counts(text.tr('J', 'I'), step: 2)
      @analysis << "digraphs pairs=#{text.length / 2} distinct=#{pairs.length}"
      @analysis << "top #{Analysis.top_pairs(pairs)}"
      square = Playfair.square(result.key).chars.each_slice(5).map(&:join)
      @analysis << "square #{square.join(' ')}"
    end
  end

  def perform_break(job)
    source = @messages.fetch(job.source)
    text = source.letters
    raise JobError, 'text too short' if text.length < 40

    keys = nil
    if job.cipher == 'playfair'
      raise JobError, 'bad playfair text' unless Playfair.valid_ciphertext?(text)

      keys = key_list(job.options.fetch('KEYS'))
      raise JobError, 'empty key list' if keys.empty?
    end
    result = break_cipher(text, job.cipher, job.options, keys)
    lines = result_lines(source, job.cipher, result.key, result.plaintext)
    header = "JOB #{job.number} BREAK #{job.cipher} source=#{job.source} key=#{result.key}"
    publish(job, header + " score=#{result.score} lines=#{lines.length}", lines)
    ranked = result.candidates
    margin = ranked.length == 1 ? 0 : ranked[0].score - ranked[1].score
    @candidates << "JOB #{job.number} BREAK #{job.cipher} source=#{job.source} tried=#{ranked.length} margin=#{margin}"
    ranked.first(job.options['TOP']).each_with_index do |candidate, index|
      @candidates << "#{index + 1} #{candidate.key} #{candidate.score} #{candidate.plaintext.byteslice(0, 40)}"
    end
    break_analysis(job, text, result)
  end

  def analyze(job)
    text = @messages.fetch(job.source).letters
    length = text.length
    raise JobError, 'text too short' if length < 40

    counts = Analysis.counts(text)
    doubles = 0
    pair_doubles = 0
    (length - 1).times do |index|
      next unless text.getbyte(index) == text.getbyte(index + 1)

      doubles += 1
      pair_doubles += 1 if index.even?
    end
    examination = Analysis.kasiski(text)
    periods = Analysis.periods(text, job.options['MAXLEN'], examination)
    @results << "JOB #{job.number} ANALYZE source=#{job.source} letters=#{length}"
    @analysis << "JOB #{job.number} ANALYZE source=#{job.source}"
    @analysis << "letters=#{length}"
    @analysis << "ioc=#{Analysis.coincidence(text)} mono=#{@weights.monogram(text)} bigram=#{@weights.bigram(text)}"
    @analysis << "doubles=#{doubles} pair_doubles=#{pair_doubles} distinct=#{counts.count(&:positive?)}"
    counts.each_with_index do |count, index|
      @analysis << "#{(index + 65).chr} #{count} #{Analysis.percentage(count, length)}"
    end
    @analysis << "bigrams #{Analysis.top_pairs(Analysis.pair_counts(text))}"
    @analysis.concat(period_lines(periods))
    @analysis.concat(kasiski_lines(examination))
  end

  def compare(job)
    first = @messages.fetch(job.source).letters
    second = @messages.fetch(job.other).letters
    header = "JOB #{job.number} COMPARE #{job.source} #{job.other}"
    if first == second
      @results << header + " equal letters=#{first.length}"
      return
    end
    common = [first.length, second.length].min
    mismatches = 0
    first_difference = nil
    common.times do |index|
      next if first.getbyte(index) == second.getbyte(index)

      mismatches += 1
      first_difference ||= index + 1
    end
    first_difference ||= common + 1
    @results << header + " differ letters=#{first.length},#{second.length} first=#{first_difference} mismatches=#{mismatches}"
  end

  def identify(job)
    source = @messages.fetch(job.source)
    text = source.letters
    raise JobError, 'text too short' if text.length < 40

    coincidence = Analysis.coincidence(text)
    average = @weights.monogram(text) / text.length
    distinct = Analysis.counts(text).count(&:positive?)
    shape = text.length.even? && !text.include?('J') && Playfair.valid_ciphertext?(text)
    family = if shape
               'playfair'
             elsif coincidence >= 5500 && average >= 44
               'transposition'
             elsif coincidence >= 5500
               'monoalphabetic'
             else
               'polyalphabetic'
             end
    keys = nil
    if family == 'playfair' && job.options.key?('KEYS')
      keys = key_list(job.options['KEYS'])
      raise JobError, 'empty key list' if keys.empty?
    end
    ciphers = case family
              when 'transposition' then %w[railfence columnar]
              when 'monoalphabetic' then ['affine']
              when 'polyalphabetic' then %w[vigenere autokey]
              else keys.nil? ? [] : ['playfair']
              end
    tried = ciphers.map { |cipher| [cipher, break_cipher(text, cipher, default_options('BREAK', cipher), keys)] }
    best = nil
    tried.each { |trial| best = trial if best.nil? || trial[1].score > best[1].score }
    header = "JOB #{job.number} IDENTIFY source=#{job.source} family=#{family}"
    if best.nil?
      @results << header
    else
      cipher, result = best
      key = result.key
      if cipher == 'affine' && key.split(',')[0] == '1'
        cipher = 'caesar'
        key = key.split(',')[1]
      end
      lines = result_lines(source, cipher, key, result.plaintext)
      @results << header + " cipher=#{cipher} key=#{key} score=#{result.score} lines=#{lines.length}"
      @results.concat(lines)
    end
    @analysis << "JOB #{job.number} IDENTIFY source=#{job.source}"
    @analysis << "letters=#{text.length} ioc=#{coincidence} mono_avg=#{average} distinct=#{distinct} shape=#{shape ? 'yes' : 'no'}"
    @analysis << "family=#{family}"
    tried.each { |name, result| @analysis << "try #{name} key=#{result.key} score=#{result.score}" }
    @analysis << "choice #{cipher}" unless best.nil?
  end

  def execute(job)
    case job.command
    when 'ENCRYPT', 'DECRYPT' then encrypt_or_decrypt(job)
    when 'BREAK' then perform_break(job)
    when 'ANALYZE' then analyze(job)
    when 'COMPARE' then compare(job)
    when 'IDENTIFY' then identify(job)
    end
  end

  def run
    read_lines('input/jobs.txt').each do |line|
      next if line.empty? || line.start_with?('#')

      @jobs += 1
      words = line.split(' ')
      command = words[0]
      begin
        execute(parse_job(words))
        @ok += 1
        @totals[command][:ok] += 1
      rescue JobError => error
        @errors += 1
        @totals[command][:errors] += 1 if @totals.key?(command)
        @results << "JOB #{@jobs} ERROR #{error.message}"
      end
    end
    COMMANDS.each do |command|
      totals = @totals.fetch(command)
      @results << "TOTAL #{command} ok=#{totals[:ok]} errors=#{totals[:errors]}"
    end
    @results << "SUMMARY jobs=#{@jobs} ok=#{@ok} errors=#{@errors} messages=#{@messages.length}"
    Dir.mkdir('output') unless Dir.exist?('output')
    {'results.txt' => @results, 'candidates.txt' => @candidates, 'analysis.txt' => @analysis}.each do |name, lines|
      File.binwrite('output/' + name, lines.empty? ? '' : lines.join("\n") + "\n")
    end
  end
end

CipherTool.new.run
