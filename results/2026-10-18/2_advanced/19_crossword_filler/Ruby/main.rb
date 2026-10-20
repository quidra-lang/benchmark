require 'set'
require_relative 'grid'
require_relative 'slots'
require_relative 'word_index'
require_relative 'filler'
require_relative 'render'

class CrosswordApplication
  Clue = Struct.new(:text, :number, :uses)
  ALPHABET = ('A'..'Z').to_a.freeze
  LETTER_POINTS = ALPHABET.zip([1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3,
                               1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10]).to_h.freeze

  def run
    read_settings
    read_words
    read_clues
    read_templates
    @seen_names = Set.new
    @templates.each do |template|
      template[:error] = check_template(template)
      next if template[:error]

      perform_attempts(template)
      template[:stats_lines] = template_statistics(template)
      template[:clue_lines] = choose_clues(template)
    end
    write_outputs
  end

  private

  def read_settings
    @params = {}
    File.readlines('input/params.txt', chomp: true).each do |line|
      next if line.empty? || line.start_with?('#')

      key, _, value = line.partition(' ')
      @params[key] = key == 'symmetry' ? value : value.to_i
    end
  end

  def read_words
    lines = File.readlines('input/words.txt', chomp: true)
    @word_lines = lines.length
    @word_invalid = []
    @word_duplicates = []
    @scores = {}
    first_lines = {}
    lines.each_with_index do |line, index|
      number = index + 1
      reason = WordIndex.word_line_error(line)
      if reason
        @word_invalid << [number, reason]
        next
      end
      word, _, score = line.partition(' ')
      if @scores.key?(word)
        @word_duplicates << [number, word, first_lines.fetch(word)]
      else
        @scores[word] = score.to_i
        first_lines[word] = number
      end
    end
    @index = WordIndex.new(@scores)
  end

  def read_clues
    @clue_entries = 0
    @clue_invalid = []
    @clue_unknown = []
    @clues = {}
    File.readlines('input/clues.txt', chomp: true).each_with_index do |line, index|
      next if line.empty? || line.start_with?('#')

      @clue_entries += 1
      reason = WordIndex.clue_line_error(line)
      if reason
        @clue_invalid << [index + 1, reason]
        next
      end
      word, _, text = line.partition('|')
      unless @scores.key?(word)
        @clue_unknown << [index + 1, word]
        next
      end
      list = (@clues[word] ||= [])
      list << Clue.new(text, list.length + 1, 0)
    end
  end

  def read_templates
    @templates = []
    current = nil
    File.readlines('input/templates.txt', chomp: true).each do |line|
      if current
        if line == 'END'
          @templates << current
          current = nil
        else
          current[:content] << line
        end
      elsif !line.empty? && !line.start_with?('#')
        current = { name: line.delete_prefix('TEMPLATE '), content: [] }
      end
    end
  end

  def interpret_options(options)
    settings = @params.slice('node_budget', 'min_score', 'symmetry')
    theme_words = []
    seen = Set.new
    options.each_with_index do |line, index|
      key, _, value = line.partition(' ')
      case key
      when 'node_budget', 'min_score'
        maximum = key == 'node_budget' ? 100_000 : 100
        valid = !seen.include?(key) && WordIndex.valid_integer?(value, 1, maximum)
        settings[key] = value.to_i if valid
      when 'symmetry'
        valid = !seen.include?(key) && %w[rot180 mirror none].include?(value)
        settings[key] = value if valid
      when 'theme'
        valid = WordIndex.valid_word?(value) && !theme_words.include?(value)
        theme_words << value if valid
      else
        valid = false
      end
      return [nil, nil, "bad option #{index + 1}"] unless valid

      seen.add(key) unless key == 'theme'
    end
    [settings, theme_words, nil]
  end

  def check_template(template)
    name = template[:name]
    duplicate = @seen_names.include?(name)
    @seen_names.add(name)
    return 'bad name' unless /\A[a-z0-9_]{1,20}\z/.match?(name)
    return 'duplicate name' if duplicate

    options, rows = template[:content].partition { |line| line.include?(' ') }
    settings, theme_words, reason = interpret_options(options)
    return reason if reason
    return 'bad height' unless rows.length.between?(3, 15)

    rows.each_with_index do |row, index|
      unless row.length.between?(3, 15) && row.length == rows.first.length &&
             /\A[.#A-Z]+\z/.match?(row)
        return "bad row #{index + 1}"
      end
    end
    grid = Grid.new(rows)
    failure = grid.symmetry_failure(settings.fetch('symmetry'))
    return "asymmetric at #{failure.join(',')}" if failure

    components = grid.components
    return "disconnected components=#{components}" unless components == 1

    runs = Slots.runs(grid)
    short = Slots.short_run(runs)
    return "short slot at #{grid.position(short.start).join(',')} #{short.direction}" if short

    layout = Slots.extract(grid, runs)
    orphan = grid.white_cells.find { |cell| layout.cell_slots[cell].empty? }
    return "orphan cell #{grid.position(orphan).join(',')}" if orphan

    initial = grid.initial_state(layout.slots.length)
    themes = Set.new
    theme_words.each_with_index do |word, index|
      return "unknown theme #{index + 1}" unless @scores.key?(word)

      slot = layout.slots.find do |entry|
        next false unless initial.assigned[entry.id].nil? && entry.length == word.length

        entry.cells.each_with_index.all? do |cell, position|
          initial.cells[cell] == '.' || initial.cells[cell] == word[position]
        end
      end
      return "theme #{index + 1} does not fit" unless slot

      initial.assigned[slot.id] = word
      slot.cells.each_with_index { |cell, position| initial.cells[cell] = word[position] }
      themes.add(slot.id)
    end
    template.merge!(settings: settings, grid: grid, layout: layout, initial: initial, themes: themes)
    nil
  end

  def perform_attempts(template)
    minimum = template[:settings].fetch('min_score')
    budget = template[:settings].fetch('node_budget')
    attempts = []
    loop do
      attempt = Filler.new(@index, template[:layout].slots, template[:initial], minimum, budget).run
      attempts << attempt
      break if attempt.outcome == 'filled' || @params.fetch('relax_step').zero? || minimum == 1

      minimum = [minimum - @params.fetch('relax_step'), 1].max
    end
    template[:attempts] = attempts
    template[:final] = attempts.last
  end

  def slot_description(template, slot)
    word = template[:final].state.assigned[slot.id]
    "#{slot.label}:#{word}:#{@scores.fetch(word)}"
  end

  def joined_or_dash(values, separator = ' ')
    values.empty? ? '-' : values.join(separator)
  end

  def template_statistics(template)
    grid = template[:grid]
    layout = template[:layout]
    slots = layout.slots
    final = template[:final]
    settings = template[:settings]
    white = grid.white_cells.length
    black = grid.cells.length - white
    givens = grid.cells.count { |cell| cell >= 'A' && cell <= 'Z' }
    symmetries = %w[rot180 mirror].select { |kind| grid.symmetry_failure(kind).nil? }
    symmetry = symmetries.empty? ? 'none' : symmetries.join(',')
    density = Render.decimal(100 * black, grid.cells.length, 1)
    across = slots.count { |slot| slot.direction == 'across' }
    lengths = slots.map(&:length).tally
    length_order = lengths.keys.sort
    length_counts = length_order.map { |length| "#{length}:#{lengths.fetch(length)}" }.join(',')
    average_length = Render.decimal(slots.sum(&:length), slots.length)
    unchecked = grid.white_cells.count { |cell| layout.cell_slots[cell].length == 1 }
    lines = ["TEMPLATE #{template[:name]}"]
    lines << "grid size=#{grid.width}x#{grid.height} blocks=#{black} white=#{white} " \
             "density=#{density} givens=#{givens} required=#{settings.fetch('symmetry')} symmetry=#{symmetry}"
    lines << "slots across=#{across} down=#{slots.length - across} total=#{slots.length} " \
             "lengths=#{length_counts} avg_length=#{average_length} longest=#{length_order.last} unchecked=#{unchecked}"
    themes = slots.select { |slot| template[:themes].include?(slot.id) }
    unless themes.empty?
      descriptions = themes.map { |slot| slot_description(template, slot) }
      lines << "themes #{descriptions.join(' ')}"
    end
    coverage = length_order.map do |length|
      supply = @index.by_length.fetch(length, []).count do |word|
        @scores.fetch(word) >= settings.fetch('min_score')
      end
      "#{length}:#{supply}"
    end
    lines << "coverage #{coverage.join(' ')}"
    initial = template[:initial]
    used = Set.new(initial.assigned.compact)
    tightest = slots.reject { |slot| initial.assigned[slot.id] }.map do |slot|
      count = @index.candidates(initial.pattern(slot), settings.fetch('min_score'), used).length
      [slot.id, count]
    end.sort_by { |id, count| [count, id] }.first(3)
    tight_labels = tightest.map { |id, count| "#{slots[id].label}:#{count}" }
    lines << "tightest #{joined_or_dash(tight_labels)}"
    template[:attempts].each_with_index do |attempt, index|
      lines << "attempt #{index + 1} min_score=#{attempt.minimum} budget=#{attempt.budget} " \
               "outcome=#{attempt.outcome} nodes=#{attempt.nodes} backtracks=#{attempt.backtracks} " \
               "prunes=#{attempt.prunes} dead_ends=#{attempt.dead_ends} max_depth=#{attempt.max_depth}"
    end
    lines << "trace #{joined_or_dash(final.trace)}"
    hotspots = slots.select { |slot| final.failures[slot.id].positive? }
                    .sort_by { |slot| [-final.failures[slot.id], slot.id] }.first(3)
    hot_labels = hotspots.map { |slot| "#{slot.label}:#{final.failures[slot.id]}" }
    lines << "hotspots #{joined_or_dash(hot_labels)}"
    if final.outcome == 'filled'
      order = final.sequence.map { |id| slots[id].label }
      lines << "order #{joined_or_dash(order)}"
      lines.concat(quality_lines(template))
    else
      lines << partial_line(template)
    end
    lines
  end

  def quality_lines(template)
    grid = template[:grid]
    layout = template[:layout]
    slots = layout.slots
    state = template[:final].state
    scores = state.assigned.map { |word| @scores.fetch(word) }
    total = scores.sum
    template[:total_score] = total
    weakest = slots.min_by { |slot| [scores[slot.id], slot.id] }
    weak = slots.select { |slot| scores[slot.id] < @params.fetch('weak_score') }
    weak_descriptions = weak.map { |slot| slot_description(template, slot) }
    quality = "quality total=#{total} average=#{Render.decimal(total, slots.length)} " \
              "weakest=#{slot_description(template, weakest)} weak=#{joined_or_dash(weak_descriptions, ',')}"
    letters = grid.white_cells.map { |cell| state.cells[cell] }
    distinct = letters.uniq
    missing = ALPHABET - distinct
    letter_points = letters.sum { |letter| LETTER_POINTS.fetch(letter) }
    checked = grid.white_cells.select { |cell| layout.cell_slots[cell].length == 2 }
    worst = checked.min_by { |cell| [layout.cell_slots[cell].sum { |id| scores[id] }, cell] }
    crossing = '-'
    unless worst.nil?
      pair = layout.cell_slots[worst].map { |id| slots[id] }
      across = pair.find { |slot| slot.direction == 'across' }
      down = pair.find { |slot| slot.direction == 'down' }
      crossing = "#{grid.position(worst).join(',')} #{across.label}:#{state.assigned[across.id]}+" \
                 "#{down.label}:#{state.assigned[down.id]}=#{scores[across.id] + scores[down.id]}"
    end
    letter_line = "letters distinct=#{distinct.length} pangram=#{missing.empty? ? 'yes' : 'no'} " \
                  "missing=#{joined_or_dash(missing, '')} scrabble=#{Render.decimal(letter_points, letters.length)} " \
                  "worst_crossing=#{crossing}"
    [quality, letter_line]
  end

  def partial_line(template)
    final = template[:final]
    state = final.state
    slots = template[:layout].slots
    white = template[:grid].white_cells
    used = Set.new(state.assigned.compact)
    blocked = slots.select do |slot|
      state.assigned[slot.id].nil? && @index.candidates(state.pattern(slot), final.minimum, used).empty?
    end.map(&:label)
    assigned = state.assigned.count { |word| !word.nil? }
    known = white.count { |cell| state.cells[cell] != '.' }
    "partial assigned=#{assigned}/#{slots.length} letters=#{known}/#{white.length} " \
      "blocked=#{joined_or_dash(blocked, ',')}"
  end

  def choose_clues(template)
    state = template[:final].state
    lines = ["TEMPLATE #{template[:name]}"]
    clued = missing = unfilled = 0
    %w[across down].each do |direction|
      slots = template[:layout].slots.select { |slot| slot.direction == direction }
      next if slots.empty?

      lines << direction.upcase
      slots.each do |slot|
        word = state.assigned[slot.id]
        chosen = nil
        score = nil
        if word
          score = @scores.fetch(word)
          chosen = @clues.fetch(word, []).min_by { |clue| [clue.uses, clue.number] }
          if chosen
            chosen.uses += 1
            clued += 1
          else
            missing += 1
          end
        else
          unfilled += 1
        end
        lines << Render.clue_line(slot, state, score, chosen&.text, template[:themes].include?(slot.id))
      end
    end
    lines << "clued=#{clued} missing=#{missing} unfilled=#{unfilled}"
    lines
  end

  def grid_paragraph(template)
    lines = ["TEMPLATE #{template[:name]}"]
    if template[:error]
      lines << "error #{template[:error]}"
    else
      final = template[:final]
      lines << "outcome=#{final.outcome} attempts=#{template[:attempts].length} min_score=#{final.minimum}"
      lines.concat(Render.grid_lines(template[:grid], final.state))
      lines << 'numbers'
      lines.concat(Render.number_lines(template[:grid], template[:layout]))
    end
    lines
  end

  def overall_paragraphs(valid)
    filled = valid.select { |template| template[:final].outcome == 'filled' }
    ranking = filled.sort do |left, right|
      comparison = (right[:total_score] * left[:layout].slots.length) <=>
                   (left[:total_score] * right[:layout].slots.length)
      comparison.zero? ? left[:name] <=> right[:name] : comparison
    end
    rank_lines = ['RANKING']
    ranking.each_with_index do |template, index|
      count = template[:layout].slots.length
      total = template[:total_score]
      rank_lines << "rank #{index + 1} #{template[:name]} average=#{Render.decimal(total, count)} " \
                    "total=#{total} entries=#{count}"
    end
    appearances = Hash.new { |hash, word| hash[word] = [] }
    filled.each do |template|
      template[:final].state.assigned.uniq.each { |word| appearances[word] << template[:name] }
    end
    reused = appearances.select { |_, names| names.length >= 2 }
                        .sort_by { |word, names| [-names.length, word] }
    reuse_lines = ['REUSE']
    reused.each do |word, names|
      reuse_lines << "reused #{word} #{names.length} #{names.join(',')}"
    end
    outcomes = valid.map { |template| template[:final].outcome }.tally
    attempts = valid.flat_map { |template| template[:attempts] }
    summary = "SUMMARY templates=#{@templates.length} invalid=#{@templates.length - valid.length} " \
              "filled=#{filled.length} unfillable=#{outcomes.fetch('unfillable', 0)} " \
              "budget=#{outcomes.fetch('budget', 0)} attempts=#{attempts.length} nodes=#{attempts.sum(&:nodes)}"
    [rank_lines, reuse_lines, [summary]]
  end

  def wordlist_lines
    lines = ["WORDLIST lines=#{@word_lines} valid=#{@scores.length} invalid=#{@word_invalid.length} " \
             "duplicates=#{@word_duplicates.length}"]
    @word_invalid.each { |number, reason| lines << "invalid #{number} #{reason}" }
    @word_duplicates.each { |number, word, first| lines << "duplicate #{number} #{word} first=#{first}" }
    @index.by_length.keys.sort.each do |length|
      words = @index.by_length.fetch(length)
      total = words.sum { |word| @scores.fetch(word) }
      lines << "length #{length} words=#{words.length} average=#{Render.decimal(total, words.length)} " \
               "best=#{words.first}:#{@scores.fetch(words.first)}"
    end
    bands = Array.new(5, 0)
    @scores.each_value { |score| bands[(score - 1) / 20] += 1 }
    band_labels = %w[1-20 21-40 41-60 61-80 81-100]
    lines << "bands #{band_labels.each_with_index.map { |label, index| "#{label}=#{bands[index]}" }.join(' ')}"
    top = @index.ranked.first(5).map { |word| "#{word}:#{@scores.fetch(word)}" }
    lines << "top #{top.join(' ')}"
    rare = ALPHABET.map do |letter|
      [letter, @scores.keys.count { |word| word.include?(letter) }]
    end.sort_by { |letter, count| [count, letter] }.first(5)
    lines << "rare_letters #{rare.map { |letter, count| "#{letter}:#{count}" }.join(' ')}"
    all_clues = @clues.values.flatten
    lines << "CLUES entries=#{@clue_entries} valid=#{all_clues.length} invalid=#{@clue_invalid.length} " \
             "unknown=#{@clue_unknown.length} words=#{@clues.length}"
    @clue_invalid.each { |number, reason| lines << "clue_invalid #{number} #{reason}" }
    @clue_unknown.each { |number, word| lines << "clue_unknown #{number} #{word}" }
    used = all_clues.count { |clue| clue.uses.positive? }
    repeated = all_clues.count { |clue| clue.uses >= 2 }
    lines << "CLUE_USE used=#{used} unused=#{all_clues.length - used} repeated=#{repeated}"
    @clues.keys.sort.each do |word|
      @clues.fetch(word).each do |clue|
        lines << "repeated #{word} clue=#{clue.number} uses=#{clue.uses}" if clue.uses >= 2
      end
    end
    lines
  end

  def write_paragraphs(path, paragraphs)
    text = paragraphs.map { |lines| lines.join("\n") }.join("\n\n")
    text += "\n" unless paragraphs.empty?
    File.write(path, text)
  end

  def write_outputs
    Dir.mkdir('output') unless Dir.exist?('output')
    valid = @templates.reject { |template| template[:error] }
    write_paragraphs('output/grid.txt', @templates.map { |template| grid_paragraph(template) })
    write_paragraphs('output/clues.txt', valid.map { |template| template[:clue_lines] })
    statistics = valid.map { |template| template[:stats_lines] } + overall_paragraphs(valid)
    write_paragraphs('output/search_stats.txt', statistics)
    File.write('output/wordlist.txt', wordlist_lines.join("\n") + "\n")
  end
end

CrosswordApplication.new.run if $PROGRAM_NAME == __FILE__
