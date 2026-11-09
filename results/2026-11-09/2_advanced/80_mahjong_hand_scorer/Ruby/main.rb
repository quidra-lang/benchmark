require 'fileutils'
require_relative 'tiles'
require_relative 'decomposition'
require_relative 'yaku'
require_relative 'scoring'
require_relative 'shanten'

module Mahjong
  WAIT_ORDER = %w[ryanmen kanchan penchan shanpon tanki single thirteen].freeze
  WIN_ORDER = %w[dealer_ron dealer_tsumo nondealer_ron nondealer_tsumo].freeze

  def self.read_records(filename)
    File.readlines("input/#{filename}", chomp: true).map do |line|
      label, *items = line.split(' ')
      [label, items.map { |item| item.split('=', 2) }.to_h]
    end
  end

  def self.situation(label, fields, rules)
    s = fields.dup
    s[:label], s[:rule] = label, rules.fetch(fields['rules'])
    %w[hand win dora ura discards].each do |key|
      s[key] = Tiles.parse(fields[key], empty: %w[ura discards].include?(key))
    end
    s[:melds] = fields['melds'] == '-' ? [] : fields['melds'].split(',').map do |text|
      tiles = Tiles.parse(text[1..])
      { type: text[0], tiles: tiles, block: tiles ? tiles.map(&:kind).sort : [] }
    end
    s[:flags] = fields['flags'] == '-' ? [] : fields['flags'].split(',')
    s[:closed] = s[:melds].all? { |m| m[:type] == 'A' }
    s[:riichi] = (s[:flags] & %w[riichi double_riichi]).any?
    s[:kans] = s[:melds].count { |m| %w[K A].include?(m[:type]) }
    s[:seat_tile] = Tiles::WIND_TILES.fetch(s['seat'])
    s[:round_tile] = Tiles::WIND_TILES.fetch(s['round'])
    s
  end

  def self.prepare(s)
    meld_tiles = s[:melds].flat_map { |m| m[:tiles] }
    s[:winning] = s['win'].first.kind
    s[:hand_counts] = Tiles.counts(s['hand'])
    s[:concealed] = Tiles.counts(s['hand'] + s['win'])
    s[:meld_counts] = Tiles.counts(meld_tiles)
    s[:all_tiles] = s['hand'] + s['win'] + meld_tiles
    s[:all_counts] = Tiles.counts(s[:all_tiles])
  end

  def self.copy_error(tiles, rule)
    reds = Array.new(3, 0)
    tiles.each { |tile| reds[tile.kind / 9] += 1 if tile.red }
    return 'red five not allowed' if !rule['red_fives'] && reds.any?(&:positive?)

    kind = Tiles.counts(tiles).index { |count| count >= 5 }
    return "too many copies of #{Tiles.name(kind)}" if kind

    suit = reds.index { |count| count >= 2 }
    "too many copies of 0#{'mps'[suit]}" if suit
  end

  def self.valid_meld?(meld)
    block, type = meld.values_at(:block, :type)
    if type == 'C'
      block.size == 3 && block.first < 27 && block.first % 9 <= 6 &&
        block == [block.first, block.first + 1, block.first + 2]
    else
      %w[P K A].include?(type) && block.size == (type == 'P' ? 3 : 4) && block.uniq.size == 1
    end
  end

  def self.validate(s)
    values = s.values_at('hand', 'win', 'dora', 'ura', 'discards') + s[:melds].map { |m| m[:tiles] }
    return 'bad tile notation' if values.any?(&:nil?) || s['win'].size != 1
    return 'bad meld' if s[:melds].size >= 5 || s[:melds].any? { |m| !valid_meld?(m) }
    return 'wrong tile count' if s['hand'].size != 13 - 3 * s[:melds].size

    prepare(s)
    error = copy_error(s[:all_tiles] + s['dora'] + s['ura'] + s['discards'], s[:rule])
    return error if error
    return 'invalid discarder' if (s['by'] == 'tsumo' && s['from'] != '-') ||
                                 (s['by'] == 'ron' && ['-', s['seat']].include?(s['from']))

    flags = s[:flags]
    valid = {
      'riichi' => s[:closed],
      'double_riichi' => s[:closed] && !flags.include?('riichi'),
      'ippatsu' => s[:riichi] && !flags.include?('rinshan'),
      'haitei' => s['by'] == 'tsumo' && !flags.include?('rinshan'),
      'houtei' => s['by'] == 'ron' && !flags.include?('chankan'),
      'rinshan' => s['by'] == 'tsumo' && s[:kans].positive?,
      'chankan' => s['by'] == 'ron',
      'tenhou' => s['seat'] == 'E' && s['by'] == 'tsumo' && s[:melds].empty? && flags == ['tenhou'],
      'chiihou' => s['seat'] != 'E' && s['by'] == 'tsumo' && s[:melds].empty? && flags == ['chiihou']
    }
    Yaku::FLAGS.each { |f| return "invalid flag #{f}" if flags.include?(f) && !valid[f] }
    return 'invalid dora indicators' if s['dora'].size != 1 + s[:kans]
    return 'invalid ura indicators' if (s[:riichi] && s['ura'].size != s['dora'].size) ||
                                       (!s[:riichi] && !s['ura'].empty?)
    return 'invalid sticks' if s[:riichi] && s['sticks'].to_i.zero?
    return 'not a winning hand' unless Decomposition.winning?(s[:concealed], s[:melds].size)

    nil
  end

  def self.candidate(type, pair, sets, chosen, form, wait)
    { type: type, pair: pair, sets: sets, chosen: chosen, form: form, wait: wait,
      yaku: [], yakuman: [], multiplier: 0, han: 0, fu: 0, base: 0, category: 'none' }
  end

  def self.candidates(s)
    result = []
    win = s[:winning]
    Decomposition.standard(s[:concealed], s[:melds].size).each do |pair, sets|
      blocks = [[pair, pair]] + sets
      blocks.uniq.select { |b| b.include?(win) }.each do |chosen|
        marked = false
        parts = blocks.map do |block|
          text = Tiles.block(block)
          if !marked && block == chosen
            text += '*'
            marked = true
          end
          text
        end
        parts += s[:melds].map { |m| m[:type] + Tiles.block(m[:block]) }
        wait = Decomposition.wait_shape('standard', chosen, win, s[:hand_counts])
        result << candidate('standard', pair, sets, chosen, (['standard'] + parts).join(' '), wait)
      end
    end
    if s[:melds].empty?
      %w[chiitoitsu kokushi].each do |type|
        valid = type == 'chiitoitsu' ? Decomposition.seven_pairs?(s[:concealed]) : Decomposition.thirteen_orphans?(s[:concealed])
        next unless valid

        kinds = (0...34).select { |k| s[:concealed][k].positive? }
        parts = kinds.map { |k| Tiles.block([k] * s[:concealed][k]) + (k == win ? '*' : '') }
        wait = Decomposition.wait_shape(type, nil, win, s[:hand_counts])
        result << candidate(type, nil, [], nil, ([type] + parts).join(' '), wait)
      end
    end
    result.sort_by { |c| c[:form] }
  end

  def self.block_facts(s, c)
    triplets, sequences, hidden_sequences = [], [], []
    c[:sets].each do |block|
      if block.first == block.last
        triplets << [block, s['by'] == 'tsumo' || block != c[:chosen], false]
      else
        sequences << block.first
        hidden_sequences << block
      end
    end
    s[:melds].each do |m|
      if m[:type] == 'C'
        sequences << m[:block].first
      else
        triplets << [m[:block], m[:type] == 'A', %w[K A].include?(m[:type])]
      end
    end
    [triplets, sequences, hidden_sequences]
  end

  def self.yakuman_names(s, c, kinds, triplets)
    names = s[:flags] & %w[tenhou chiihou]
    names << 'tsuuiisou' if kinds.all? { |k| Tiles.honor?(k) }
    names << 'chinroutou' if kinds.all? { |k| Tiles.terminal?(k) }
    names << 'ryuuiisou' if (kinds - Tiles::GREEN).empty?
    suits = kinds.map { |k| k / 9 }.uniq
    if s[:melds].empty? && suits.size == 1 && suits.first < 3
      start = suits.first * 9
      counts = s[:all_counts].slice(start, 9)
      if counts.first >= 3 && counts.last >= 3 && counts[1, 7].all?(&:positive?)
        names << (s[:hand_counts].slice(start, 9) == [3, 1, 1, 1, 1, 1, 1, 1, 3] ? 'junsei_chuuren' : 'chuuren')
      end
    end
    names << (c[:wait] == 'thirteen' ? 'kokushi_13' : 'kokushi') if c[:type] == 'kokushi'
    if c[:type] == 'standard'
      tk = triplets.map { |block, _, _| block.first }
      hidden = triplets.count { |_, concealed, _| concealed }
      names << (c[:wait] == 'tanki' ? 'suuankou_tanki' : 'suuankou') if hidden == 4
      names << 'daisangen' if (tk & [31, 32, 33]).size == 3
      winds = (tk & [27, 28, 29, 30]).size
      names << 'daisuushii' if winds == 4
      names << 'shousuushii' if winds == 3 && (27..30).cover?(c[:pair])
      names << 'suukantsu' if triplets.count { |_, _, kan| kan } == 4
    end
    names
  end

  def self.ordinary_names(s, c, kinds, triplets, sequences, concealed_sequences)
    names = s[:flags] & Yaku::FLAGS.first(7)
    names << 'menzen_tsumo' if s[:closed] && s['by'] == 'tsumo'
    names << 'tanyao' if kinds.none? { |k| Tiles.yaochuu?(k) } && (s[:closed] || s[:rule]['open_tanyao'])
    names << 'honroutou' if kinds.all? { |k| Tiles.yaochuu?(k) }
    suits = kinds.select { |k| k < 27 }.map { |k| k / 9 }.uniq
    honors = kinds.any? { |k| Tiles.honor?(k) }
    names << (honors ? 'honitsu' : 'chinitsu') if suits.size == 1
    names << 'chiitoitsu' if c[:type] == 'chiitoitsu'
    return names unless c[:type] == 'standard'

    pair = c[:pair]
    yakuhai_pair = pair >= 31 || [s[:seat_tile], s[:round_tile]].include?(pair)
    if s[:closed] && s[:melds].empty? && concealed_sequences.size == 4 && !yakuhai_pair && c[:wait] == 'ryanmen'
      names << 'pinfu'
    end
    repeats = concealed_sequences.tally.values
    if s[:closed] && concealed_sequences.size == 4 && repeats.sum { |n| n / 2 } == 2
      names << 'ryanpeikou'
    elsif s[:closed] && repeats.any? { |n| n >= 2 }
      names << 'iipeikou'
    end
    tk = triplets.map { |block, _, _| block.first }
    [[31, 'haku'], [32, 'hatsu'], [33, 'chun'], [s[:seat_tile], 'jikaze'], [s[:round_tile], 'bakaze']].each do |kind, name|
      names << name if tk.include?(kind)
    end
    names << 'toitoi' if triplets.size == 4
    names << 'sanankou' if triplets.count { |_, hidden, _| hidden } == 3
    names << 'sanshoku_doujun' if (0...7).any? { |n| 3.times.all? { |suit| sequences.include?(n + suit * 9) } }
    names << 'sanshoku_doukou' if (0...9).any? { |n| 3.times.all? { |suit| tk.include?(n + suit * 9) } }
    names << 'ittsu' if 3.times.any? { |suit| [0, 3, 6].all? { |n| sequences.include?(suit * 9 + n) } }
    blocks = [[pair, pair]] + c[:sets] + s[:melds].map { |m| m[:block] }
    if !sequences.empty? && blocks.all? { |b| b.any? { |k| Tiles.yaochuu?(k) } }
      names << (honors ? 'chanta' : 'junchan')
    end
    names << 'sankantsu' if triplets.count { |_, _, kan| kan } == 3
    names << 'shousangen' if (tk & [31, 32, 33]).size == 2 && pair >= 31
    names
  end

  def self.evaluate(s)
    kinds = (0...34).select { |k| s[:all_counts][k].positive? }
    candidates(s).each do |c|
      triplets, sequences, hidden_sequences = block_facts(s, c)
      names = yakuman_names(s, c, kinds, triplets)
      c[:yakuman] = Yaku.yakuman(names, s[:rule]['double_yakuman'])
      unless c[:yakuman].empty?
        c[:multiplier] = c[:yakuman].sum(&:last)
        c[:base], c[:category] = 8000 * c[:multiplier], 'yakuman'
        next
      end
      names = ordinary_names(s, c, kinds, triplets, sequences, hidden_sequences)
      c[:yaku] = Yaku.ordinary(names, s[:closed])
      c[:dora] = s['dora'].sum { |t| s[:all_counts][Tiles.next_dora(t.kind)] }
      c[:ura] = s['ura'].sum { |t| s[:all_counts][Tiles.next_dora(t.kind)] }
      c[:aka] = s[:all_tiles].count(&:red)
      c[:fu_items], c[:fu_total], c[:fu] = Scoring.fu(c[:type], c[:pair], triplets, c[:wait],
        s[:closed], s['by'], s[:seat_tile], s[:round_tile], names.include?('pinfu'))
      next if c[:yaku].empty?

      c[:han] = c[:yaku].sum(&:last) + c[:dora] + c[:ura] + c[:aka]
      c[:category], c[:base] = Scoring.limit(c[:han], c[:fu], s[:rule])
    end
  end

  def self.best(candidates)
    candidates.select { |c| c[:base].positive? }.min_by do |c|
      [-c[:base], c[:yakuman].empty? ? 0 : -1, -c[:han], -c[:fu], c[:form]]
    end
  end

  def self.candidate_line(c)
    evaluation = if !c[:yakuman].empty?
                   "yakuman #{c[:multiplier]} base #{c[:base]} yaku #{c[:yakuman].map(&:first).join(',')}"
                 elsif c[:yaku].empty?
                   'no_yaku'
                 else
                   "han #{c[:han]} fu #{c[:fu]} base #{c[:base]} yaku #{c[:yaku].map(&:first).join(',')}"
                 end
    "CANDIDATE #{c[:form]} = #{c[:wait]} #{evaluation}"
  end

  def self.winning_lines(s, c)
    lines = ["FORM #{c[:form]}", "WAIT #{c[:wait]}"]
    if !c[:yakuman].empty?
      c[:yakuman].each { |name, value| lines << "YAKUMAN #{name} #{value}" }
      lines << "SCORE yakuman #{c[:multiplier]} base #{c[:base]}"
    else
      c[:yaku].each { |name, value| lines << "YAKU #{name} #{value}" }
      lines << "DORA dora #{c[:dora]} aka #{c[:aka]} ura #{c[:ura]}"
      c[:fu_items].each { |name, value| lines << "FU #{name} #{value}" }
      lines << "FU total #{c[:fu_total]} #{c[:fu]}"
      lines << "SCORE han #{c[:han]} fu #{c[:fu]} limit #{c[:category]} base #{c[:base]}"
    end
    ron, dealer, other, points = Scoring.payments(c[:base], s['seat'] == 'E', s['by'])
    lines << if s['by'] == 'ron'
               "PAY ron #{ron}"
             elsif s['seat'] == 'E'
               "PAY tsumo all #{other}"
             else
               "PAY tsumo dealer #{dealer} nondealer #{other}"
             end
    honba = s['honba'].to_i * s[:rule]['honba']
    sticks = s['sticks'].to_i * 1000
    gain = points + honba + sticks
    lines << "BONUS honba #{honba} sticks #{sticks}"
    lines << "TOTAL points #{points} gain #{gain}"
    delta = Tiles::WINDS.to_h { |w| [w, 0] }
    if s['by'] == 'ron'
      delta[s['from']] = -ron - honba
    else
      Tiles::WINDS.each do |wind|
        delta[wind] = -(wind == 'E' ? dealer : other) - honba / 3 unless wind == s['seat']
      end
    end
    delta[s['seat']] = gain
    lines << 'DELTA ' + delta.map { |w, n| "#{w} #{n.positive? ? "+#{n}" : n}" }.join(' ')
    [lines, points]
  end

  class Reports
    def initialize
      @rules = Mahjong.read_records('rules.txt').to_h.transform_values do |fields|
        fields.to_h { |key, value| [key, key == 'honba' ? value.to_i : value == 'yes'] }
      end
      @situations = Mahjong.read_records('hands.txt')
      @hands = Mahjong.read_records('waits.txt')
      @stats, @wins, @waits, @han, @fu, @limits, @yaku = Array.new(7) { Hash.new(0) }
      @rule_counts = @rules.to_h { |name, _| [name, Hash.new(0)] }
      @maximum, @maximum_label = 0, '-'
      @summary = ['hand,han,fu,points,yaku']
    end

    def scores
      lines = []
      @situations.each do |label, fields|
        s = Mahjong.situation(label, fields, @rules)
        @rule_counts[fields['rules']]['hands'] += 1
        lines << "HAND #{label}"
        error = Mahjong.validate(s)
        if error
          @stats['errors'] += 1
          lines << "ERROR #{error}"
          @summary << "#{label},-,-,0,ERROR"
          next
        end
        waiting = Decomposition.waiting_tiles(s[:hand_counts], s[:meld_counts], s[:melds].size)
        lines << 'WAITS ' + waiting.map { |k| Tiles.name(k) }.join(' ')
        evaluated = Mahjong.evaluate(s)
        lines.concat(evaluated.map { |c| Mahjong.candidate_line(c) })
        result = if s['by'] == 'ron' && s['discards'].any? { |t| waiting.include?(t.kind) }
                   'furiten'
                 elsif Mahjong.best(evaluated).nil?
                   'no_yaku'
                 end
        if result
          @stats[result] += 1
          lines << "RESULT #{result}"
          @summary << "#{label},-,-,0,#{result.upcase}"
          next
        end
        c = Mahjong.best(evaluated)
        report, points = Mahjong.winning_lines(s, c)
        lines.concat(report)
        record_win(s, c, points)
      end
      lines.concat(score_statistics)
    end

    def record_win(s, c, points)
      @stats['wins'] += 1
      @stats['points'] += points
      @rule_counts[s['rules']]['wins'] += 1
      @rule_counts[s['rules']]['points'] += points
      @wins[(s['seat'] == 'E' ? 'dealer_' : 'nondealer_') + s['by']] += 1
      @waits[c[:wait]] += 1
      @limits[c[:category]] += 1
      names = c[:yakuman].empty? ? c[:yaku] : c[:yakuman]
      names.each { |name, _| @yaku[name] += 1 }
      if c[:yakuman].empty?
        han, fu = c.values_at(:han, :fu)
        @han[han] += 1
        @fu[fu] += 1
      else
        han, fu = "Y#{c[:multiplier]}", '-'
      end
      @summary << "#{s[:label]},#{han},#{fu},#{points},#{names.map(&:first).join(';')}"
      @maximum, @maximum_label = points, s[:label] if points > @maximum
    end

    def score_statistics
      lines = ["STATS hands #{@situations.size} wins #{@stats['wins']} furiten #{@stats['furiten']} no_yaku #{@stats['no_yaku']} errors #{@stats['errors']}",
               'WINS ' + WIN_ORDER.map { |n| "#{n} #{@wins[n]}" }.join(' '),
               'WAIT_COUNT ' + WAIT_ORDER.map { |n| "#{n} #{@waits[n]}" }.join(' ')]
      @han.sort.each { |n, count| lines << "HAN_COUNT #{n} #{count}" }
      @fu.sort.each { |n, count| lines << "FU_COUNT #{n} #{count}" }
      Yaku::CATEGORIES.each { |n| lines << "LIMIT #{n} #{@limits[n]}" }
      (Yaku::YAKU + Yaku::YAKUMAN).each do |name, *_|
        lines << "YAKU_COUNT #{name} #{@yaku[name]}" if @yaku[name].positive?
      end
      lines << "POINTS total #{@stats['points']} max #{@maximum} hand #{@maximum_label}"
      @rule_counts.each do |name, counts|
        lines << "RULE #{name} hands #{counts['hands']} wins #{counts['wins']} points #{counts['points']}"
      end
      lines
    end

    def tenpai_lines(label, fields, accepted, furiten)
      lines, best = [], {}
      accepted.each do |kind, left|
        results = {}
        %w[ron tsumo].each do |method|
          if method == 'ron' && furiten
            results[method] = 'furiten'
            next
          end
          hypothetical = fields.merge('melds' => '-', 'win' => Tiles.name(kind), 'by' => method,
            'from' => '-', 'flags' => fields['riichi'] == 'yes' ? 'riichi' : '-',
            'ura' => '-', 'honba' => '0', 'sticks' => '0')
          s = Mahjong.situation(label, hypothetical, @rules)
          Mahjong.prepare(s)
          c = Mahjong.best(Mahjong.evaluate(s))
          unless c
            results[method] = 'no_yaku'
            next
          end
          points = Scoring.payments(c[:base], fields['seat'] == 'E', method).last
          results[method] = points
          best[method] = [kind, points] if !best[method] || points > best[method].last
        end
        lines << "WAIT #{Tiles.name(kind)} left #{left} ron #{results['ron']} tsumo #{results['tsumo']}"
      end
      choices = %w[ron tsumo].to_h do |method|
        value = best[method]
        [method, value ? "#{Tiles.name(value.first)} #{value.last}" : 'none']
      end
      lines << "BEST ron #{choices['ron']} tsumo #{choices['tsumo']}"
    end

    def waits
      lines, stats, frequencies = [], Hash.new(0), Hash.new(0)
      @hands.each do |label, fields|
        lines << "HAND #{label}"
        parsed = %w[hand dora discards visible].to_h do |key|
          [key, Tiles.parse(fields[key], empty: %w[discards visible].include?(key))]
        end
        error = if parsed.values.any?(&:nil?)
                  'bad tile notation'
                elsif parsed['hand'].size != 13
                  'wrong tile count'
                else
                  Mahjong.copy_error(parsed.values.flatten, @rules[fields['rules']])
                end
        if error
          stats['errors'] += 1
          lines << "ERROR #{error}"
          next
        end
        counts = Tiles.counts(parsed['hand'])
        known = Tiles.counts(parsed.values.flatten)
        standard, seven, orphans = Shanten.numbers(counts)
        current = [standard, seven, orphans].min
        frequencies[current] += 1
        lines << "SHANTEN standard #{standard} chiitoitsu #{seven} kokushi #{orphans}"
        accepted = (0...34).filter_map do |kind|
          next if counts[kind] >= 4

          counts[kind] += 1
          advancing = Shanten.numbers(counts).min < current
          counts[kind] -= 1
          [kind, 4 - known[kind]] if advancing
        end
        total = accepted.sum(&:last)
        if current != 0
          suffix = accepted.map { |kind, left| " #{Tiles.name(kind)}:#{left}" }.join
          lines << "ACCEPT kinds #{accepted.size} tiles #{total}#{suffix}"
          next
        end
        stats['tenpai'] += 1
        furiten = accepted.any? { |kind, _| parsed['discards'].any? { |t| t.kind == kind } }
        stats['furiten'] += 1 if furiten
        lines << "TENPAI kinds #{accepted.size} tiles #{total} furiten #{furiten ? 'yes' : 'no'}"
        lines.concat(tenpai_lines(label, fields, accepted, furiten))
      end
      lines << "STATS hands #{@hands.size} errors #{stats['errors']} tenpai #{stats['tenpai']} furiten #{stats['furiten']}"
      7.times { |n| lines << "SHANTEN_COUNT #{n} #{frequencies[n]}" }
      lines
    end

    def write
      score_lines = scores
      wait_lines = waits
      FileUtils.mkdir_p('output')
      { 'scores.txt' => score_lines, 'waits.txt' => wait_lines, 'summary.csv' => @summary }.each do |name, lines|
        File.write("output/#{name}", lines.join("\n") + "\n")
      end
    end
  end
end

Mahjong::Reports.new.write if $PROGRAM_NAME == __FILE__
