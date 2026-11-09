require 'fileutils'
require_relative 'board'
require_relative 'dictionary_trie'
require_relative 'move_generator'
require_relative 'scoring'
require_relative 'game'

class Scrabble
  LETTERS = MoveGenerator::LETTERS
  VOWELS = 'AEIOU'
  STRATEGIES = %w[score tiles equity].freeze
  Evaluated = Data.define(:move, :score, :new_tiles, :words, :leave, :value)

  def self.read_inputs
    values, counts, weights = {}, {}, {}
    File.readlines('input/tiles.txt', chomp: true).each do |line|
      next if line.empty? || line.start_with?('#')
      letter, value, count, weight = line.split
      values[letter], counts[letter], weights[letter] = value.to_i, count.to_i, weight.to_i
    end
    trie = DictionaryTrie.new
    stats, lengths = Hash.new(0), Hash.new(0)
    File.readlines('input/dictionary.txt', chomp: true).each do |line|
      next if line.empty? || line.start_with?('#')
      stats[:lines] += 1
      if !/\A[A-Z]{2,15}\z/.match?(line)
        stats[:skipped] += 1
      elsif trie.add(line)
        lengths[line.size] += 1
      else
        stats[:duplicates] += 1
      end
    end
    jobs, current = [], nil
    File.readlines('input/jobs.txt', chomp: true).each do |line|
      if !current
        current = [line] unless line.empty? || line.start_with?('#')
      elsif line == 'END'
        jobs << current
        current = nil
      else
        current << line
      end
    end
    dictionary_lines = ["DICTIONARY lines=#{stats[:lines]} words=#{trie.words} skipped=#{stats[:skipped]} duplicates=#{stats[:duplicates]} nodes=#{trie.nodes}",
                        'lengths' + lengths.sort.map { |length, count| " #{length}=#{count}" }.join]
    [values, counts, weights, trie, jobs, dictionary_lines]
  end

  def initialize(values, counts, weights, trie)
    @values, @counts, @weights, @trie = values, counts, weights, trie
    @topn_totals, @validation_totals, @game_totals = Hash.new(0), Hash.new(0), Hash.new(0)
  end

  def valid_name?(value)
    /\A[a-z0-9_]{1,20}\z/.match?(value)
  end

  def valid_number?(value, low, high)
    /\A(?:0|[1-9][0-9]*)\z/.match?(value) && value.to_i.between?(low, high)
  end

  def valid_rack?(value)
    /\A[A-Z?]{1,7}\z/.match?(value)
  end

  def collection(value)
    value.empty? ? '-' : value.chars.sort.join
  end

  def tile_kind(letter)
    /[A-Z]/.match?(letter) ? letter : '?'
  end

  def remove_tiles(rack, removed)
    counts = Hash.new(0).merge(rack.chars.tally)
    removed.each { |letter| counts[letter] -= 1 }
    counts.sort.map { |letter, count| letter * count }.join
  end

  def notation(evaluated)
    "#{Board.position(evaluated.move)} #{evaluated.move.word}"
  end

  def standard_key(item)
    move = item.move
    [-item.score, move.row, move.column, move.direction, move.word]
  end

  def strategy_key(item, strategy)
    prefix = case strategy
             when 'tiles' then [-item.new_tiles.size]
             when 'equity' then [-item.score - item.value]
             else []
             end
    prefix + standard_key(item)
  end

  def used_tiles(board)
    Hash.new(0).merge(Board.tiles(board).map { |_, _, letter| tile_kind(letter) }.tally)
  end

  def tile_error(board, rack)
    used = used_tiles(board)
    rack.each_char { |letter| used[letter] += 1 }
    Game::TILE_ORDER.each_char do |letter|
      return "too many #{letter}" if used[letter] > @counts[letter]
    end
    nil
  end

  def unseen(board, rack)
    used = used_tiles(board)
    rack.each_char { |letter| used[letter] += 1 }
    Game::TILE_ORDER.chars.map { |letter| letter * (@counts[letter] - used[letter]) }.join
  end

  def board_error(board, rack)
    return "board rows #{board.size}" unless board.size == Board::SIZE
    board.each_with_index do |row, index|
      return "bad board row #{index + 1}" unless /\A[.A-Za-z]{15}\z/.match?(row.join)
    end
    error = tile_error(board, rack)
    return error if error
    return 'center empty' if !Board.tiles(board).empty? && board[7][7] == '.'
    return 'disconnected' unless Board.connected?(board)
    Board.words(board).each do |word|
      return "unknown word #{word.word} at #{Board.position(word)}" unless @trie.include?(word.word.upcase)
    end
    nil
  end

  def job_error(job, seen)
    kind, name, count, order = job.first.split
    return 'bad name' unless valid_name?(name)
    return 'duplicate name' if seen.include?(name)
    if kind == 'TOPN'
      return 'bad count' unless valid_number?(count, 1, 99)
      return 'bad order' unless STRATEGIES.include?(order)
      rack = job[1].split[1]
      return 'bad rack' unless valid_rack?(rack)
      return board_error(job.drop(3).map(&:chars), rack)
    end
    if kind == 'VALIDATE'
      rows = job.drop(2).take_while { |line| !line.start_with?('MOVE') }.map(&:chars)
      return board_error(rows, '')
    end
    return 'bad seed' unless valid_number?(count, 1, 2147483646)
    return "bad player count #{job.size - 1}" unless (job.size - 1).between?(2, 4)
    names = Set.new
    job.drop(1).each_with_index do |line, index|
      _, player, strategy, threshold = line.split
      return "bad player #{index + 1}" unless valid_name?(player) && STRATEGIES.include?(strategy)
      return "bad player #{index + 1}" if kind == 'GAME' && !valid_number?(threshold, 0, 99)
      return "duplicate player #{index + 1}" if names.include?(player)
      names.add(player)
    end
    nil
  end

  def leave_value(rack)
    counts = Hash.new(0).merge(rack.chars.tally)
    duplicates = LETTERS.each_char.reduce(0) { |total, letter| total + [0, counts[letter] - 1].max }
    vowels = rack.each_char.count { |letter| VOWELS.include?(letter) }
    consonants = rack.each_char.count { |letter| LETTERS.include?(letter) && !VOWELS.include?(letter) }
    rack.each_char.reduce(0) { |total, letter| total + @weights[letter] } - 4 * duplicates - 3 * [0, (vowels - consonants).abs - 1].max
  end

  def best_leave(rack)
    candidates = ['']
    rack.chars.tally.sort.each do |letter, count|
      candidates = candidates.flat_map { |prefix| (0..count).map { |quantity| prefix + letter * quantity } }
    end
    candidates.reject { |candidate| candidate.size == rack.size }.min_by { |candidate| [-leave_value(candidate), -candidate.size, candidate] }
  end

  def evaluate(board, rack, move)
    score, new_tiles, word_scores = Scoring.score_move(board, move, @values)
    leave = remove_tiles(rack, new_tiles.map { |_, _, letter| tile_kind(letter) })
    words = word_scores.map { |word, value| "#{word.word}:#{value}" }.join(',')
    Evaluated.new(move, score, new_tiles, words, leave, leave_value(leave))
  end

  def legal_moves(board, rack)
    MoveGenerator.generate(board, rack, @trie).map { |move| evaluate(board, rack, move) }.sort_by { |item| standard_key(item) }
  end

  def position_summary(board)
    words, occupied = Board.words(board), Board.tiles(board)
    longest = words.each_with_index.min_by { |word, index| [-word.word.size, index] }&.first&.word || '-'
    blanks = occupied.count { |_, _, letter| /[a-z]/.match?(letter) }
    premiums = Hash.new(0).merge(occupied.map { |row, column, _| Board::PREMIUMS[row][column] }.tally)
    "position tiles=#{occupied.size} words=#{words.size} longest=#{longest} blanks=#{blanks} premiums=TW:#{premiums['#']},DW:#{premiums['*']},TL:#{premiums['^']},DL:#{premiums['+']}"
  end

  def topn(job)
    _, name, count, order = job.first.split
    count = count.to_i
    rack = job[1].split[1]
    board = job.drop(3).map(&:chars)
    moves = legal_moves(board, rack)
    shown = moves.sort_by { |item| strategy_key(item, order) }.first(count)
    hidden = unseen(board, rack)
    checks = [board, Board.transpose(board)].map do |position|
      values = MoveGenerator.cross_checks(position, @trie).values
      "#{values.size},#{values.count(&:empty?)},#{values.reduce(0) { |total, allowed| total + allowed.size }}"
    end
    across = moves.count { |item| item.move.direction == 0 }
    bingos = moves.count { |item| item.new_tiles.size == Scoring::RACK_SIZE }
    blanks = moves.count { |item| item.new_tiles.any? { |_, _, letter| /[a-z]/.match?(letter) } }
    vowels = rack.each_char.count { |letter| VOWELS.include?(letter) }
    consonants = rack.each_char.count { |letter| LETTERS.include?(letter) && !VOWELS.include?(letter) }
    lines = ["TOPN #{name} n=#{count} order=#{order} rack=#{collection(rack)}",
             "board tiles=#{Board.tiles(board).size} anchors=#{MoveGenerator.anchors(board).size}",
             "unseen count=#{hidden.size} tiles=#{collection(hidden)}",
             "rack vowels=#{vowels} consonants=#{consonants} blanks=#{rack.count('?')} value=#{Game.points(rack, @values)}",
             "checks across=#{checks[0]} down=#{checks[1]}",
             "moves total=#{moves.size} across=#{across} down=#{moves.size - across} bingos=#{bingos} blanks=#{blanks}"]
    lines << 'best_by_tiles' + (1..7).map { |number| " #{number}=#{moves.select { |item| item.new_tiles.size == number }.map(&:score).max || '-'}" }.join
    keep = best_leave(rack)
    lines << "exchange keep=#{collection(keep)} value=#{leave_value(keep)}"
    anagrams = @trie.anagrams(rack).sort_by { |word| [-word.size, word] }
    lines << "anagrams total=#{anagrams.size} top=#{anagrams.empty? ? '-' : anagrams.first(10).join(',')}"
    Board.words(board).each do |word|
      next if word.word.size < 3
      front = LETTERS.chars.select { |letter| @trie.include?(letter + word.word.upcase) }.join
      back = LETTERS.chars.select { |letter| @trie.include?(word.word.upcase + letter) }.join
      lines << "hook #{Board.position(word)} #{word.word} front=#{front.empty? ? '-' : front} back=#{back.empty? ? '-' : back}" unless front.empty? && back.empty?
    end
    nets = nil
    if hidden.size.between?(1, 7) && !shown.empty?
      nets = shown.map do |item|
        replies = legal_moves(Scoring.apply(board, item.new_tiles), hidden)
        item.score - (replies.empty? ? 0 : replies.first.score)
      end
      best = nets.each_index.min_by { |index| [-nets[index], index] }
      lines << "endgame opponent=#{collection(hidden)} best=#{best + 1} net=#{nets[best]}"
    end
    shown.each_with_index do |item, index|
      net = nets ? " net=#{nets[index]}" : ''
      lines << "#{index + 1} #{notation(item)} score=#{item.score} tiles=#{item.new_tiles.size} leave=#{collection(item.leave)} value=#{item.value}#{net} words=#{item.words}"
    end
    @topn_totals[:moves] += moves.size
    @topn_totals[:bingos] += bingos
    lines
  end

  def record_error(board, player, rack, action)
    return ['bad player', nil] unless valid_name?(player)
    return ['bad rack', nil] unless valid_rack?(rack)
    error = tile_error(board, rack)
    return [error, nil] if error
    return [nil, nil] if action == ['PASS']
    if action.first == 'EXCHANGE'
      returned = action[1]
      return ['bad exchange', nil] unless valid_rack?(returned)
      available, requested = Hash.new(0).merge(rack.chars.tally), returned.chars.tally
      returned.each_char { |letter| return ["rack lacks #{letter}", nil] if requested[letter] > available[letter] }
      return [nil, nil]
    end
    parsed = Board.parse_position(action.first)
    return ['bad position', nil] unless parsed
    word = action[1]
    return ['bad word', nil] unless /\A[A-Za-z]{2,15}\z/.match?(word)
    move = Board::Move.new(*parsed, word)
    cells = Scoring.squares(move)
    return ['off board', nil] unless cells.all? { |row, column, _| Board.inside?(row, column) }
    cells.each do |row, column, letter|
      return ["mismatch at #{Board.square_name(row, column)}", nil] unless board[row][column] == '.' || board[row][column] == letter
    end
    dr, dc = move.direction, 1 - move.direction
    before = [move.row - dr, move.column - dc]
    after = [move.row + dr * word.size, move.column + dc * word.size]
    return ['not whole word', nil] if [before, after].any? { |row, column| Board.inside?(row, column) && board[row][column] != '.' }
    new_tiles = Scoring.placement(board, move)
    return ['no new tiles', nil] if new_tiles.empty?
    available = Hash.new(0).merge(rack.chars.tally)
    new_tiles.each do |_, _, letter|
      kind = tile_kind(letter)
      return ["rack lacks #{kind}", nil] if available[kind] == 0
      available[kind] -= 1
    end
    if Board.tiles(board).empty?
      return ['center not covered', nil] unless new_tiles.any? { |row, column, _| [row, column] == Board::CENTER }
    elsif !new_tiles.any? { |row, column, _| Board.neighbors(row, column).any? { |r, c| board[r][c] != '.' } }
      return ['not connected', nil]
    end
    [move, *Scoring.cross_words(board, move)].each do |formed|
      return ["unknown word #{formed.word} at #{Board.position(formed)}", nil] unless @trie.include?(formed.word.upcase)
    end
    [nil, move]
  end

  def validate(job)
    name = job.first.split[1]
    board = job[2, Board::SIZE].map(&:chars)
    records = job.drop(2 + Board::SIZE)
    lines, players, totals = ["VALIDATE #{name}"], {}, Hash.new(0)
    records.each_with_index do |line, index|
      _, player, rack, *action = line.split
      prefix = "move #{index + 1} #{player} #{action.join(' ')}"
      error, move = record_error(board, player, rack, action)
      if error != 'bad player'
        players[player] ||= Hash.new(0)
        players[player][:moves] += 1
      end
      if error
        lines << prefix + ' invalid ' + error
        totals[:invalid] += 1
        next
      end
      legal = legal_moves(board, rack)
      best = legal.empty? ? 0 : legal.first.score
      evaluated = evaluate(board, rack, move) if move
      score = move ? evaluated.score : 0
      statistics = players[player]
      statistics[:valid] += 1
      statistics[:score] += score
      statistics[:loss] += best - score
      totals[:valid] += 1
      totals[:score] += score
      totals[:best] += best
      totals[:loss] += best - score
      if move
        rank = legal.index { |candidate| candidate.new_tiles.sort == evaluated.new_tiles.sort } + 1
        lines << "#{prefix} score=#{score} total=#{statistics[:score]} tiles=#{evaluated.new_tiles.size} rank=#{rank}/#{legal.size} best=#{best} words=#{evaluated.words}"
        board = Scoring.apply(board, evaluated.new_tiles)
      else
        lines << "#{prefix} score=0 total=#{statistics[:score]} moves=#{legal.size} best=#{best}"
      end
    end
    players.each do |player, stats|
      lines << "player #{player} moves=#{stats[:moves]} valid=#{stats[:valid]} score=#{stats[:score]} loss=#{stats[:loss]}"
    end
    lines << "total valid=#{totals[:valid]} invalid=#{totals[:invalid]} score=#{totals[:score]} best=#{totals[:best]} loss=#{totals[:loss]}"
    lines << position_summary(board)
    lines.concat(Board.display(board))
    @validation_totals[:moves] += records.size
    %i[valid invalid loss].each { |key| @validation_totals[key] += totals[key] }
    lines
  end

  def ordinary_game(job)
    _, name, seed = job.first.split
    random = Game::Minstd.new(seed.to_i)
    bag = Game.make_bag(@counts, random)
    board = Array.new(Board::SIZE) { Array.new(Board::SIZE, '.') }
    players = []
    lines = ["GAME #{name} seed=#{seed.to_i} players=#{job.size - 1}"]
    job.drop(1).each_with_index do |line, index|
      _, player, strategy, threshold = line.split
      players << {name: player, strategy: strategy, threshold: threshold.to_i, rack: Game.draw(bag, 7), score: 0, stats: Hash.new(0)}
      lines << "player #{index + 1} #{player} strategy=#{strategy} threshold=#{threshold.to_i}"
    end
    turn, consecutive, outgoing, highlight = 0, 0, nil, nil
    loop do
      index = turn % players.size
      player = players[index]
      turn += 1
      rack, stats = player.values_at(:rack, :stats)
      legal = legal_moves(board, rack)
      candidate = legal.min_by { |item| strategy_key(item, player[:strategy]) }
      prefix = "turn #{turn} #{player[:name]} rack=#{collection(rack)} moves=#{legal.size}"
      if candidate && !(candidate.score < player[:threshold] && bag.size >= 7)
        best = legal.first.score
        board = Scoring.apply(board, candidate.new_tiles)
        player[:score] += candidate.score
        drawn = Game.draw(bag, 7 - candidate.leave.size)
        player[:rack] = candidate.leave + drawn
        stats[:plays] += 1
        stats[:bingos] += 1 if candidate.new_tiles.size == 7
        stats[:top] = [stats[:top], candidate.score].max
        stats[:loss] += best - candidate.score
        consecutive = 0
        highlight = [turn, player[:name], candidate] if !highlight || candidate.score > highlight[2].score
        lines << "#{prefix} best=#{best} play #{notation(candidate)} score=#{candidate.score} total=#{player[:score]} draw=#{collection(drawn)} bag=#{bag.size}"
        if player[:rack].empty? && bag.empty?
          outgoing = index
          break
        end
      elsif bag.size >= 7
        keep = best_leave(rack)
        returned = remove_tiles(rack, keep.chars)
        drawn = Game.exchange(bag, returned, random)
        player[:rack] = keep + drawn
        stats[:exchanges] += 1
        consecutive += 1
        lines << "#{prefix} exchange keep=#{collection(keep)} draw=#{collection(drawn)} bag=#{bag.size}"
      else
        stats[:passes] += 1
        consecutive += 1
        lines << "#{prefix} pass bag=#{bag.size}"
      end
      break if consecutive == 6
    end
    lines << (outgoing ? "end reason=out player=#{players[outgoing][:name]} turns=#{turn}" : "end reason=scoreless turns=#{turn}")
    adjustments = players.map { |player| -Game.points(player[:rack], @values) }
    if outgoing
      adjustments[outgoing] = players.each_with_index.reduce(0) { |total, (player, index)| total + (index == outgoing ? 0 : Game.points(player[:rack], @values)) }
    end
    final_scores = players.each_with_index.map { |player, index| player[:score] + adjustments[index] }
    players.each_with_index do |player, index|
      adjustment = adjustments[index]
      signed = adjustment > 0 ? "+#{adjustment}" : adjustment.to_s
      lines << "final #{player[:name]} score=#{player[:score]} rack=#{collection(player[:rack])} adjust=#{signed} total=#{final_scores[index]}"
    end
    standings = players.each_index.sort_by { |index| [-final_scores[index], index] }
    standings.each_with_index do |index, rank|
      player = players[index]
      stats = player[:stats]
      lines << "standing #{rank + 1} #{player[:name]} total=#{final_scores[index]} plays=#{stats[:plays]} bingos=#{stats[:bingos]} exchanges=#{stats[:exchanges]} passes=#{stats[:passes]} top=#{stats[:top]} loss=#{stats[:loss]}"
    end
    winners = players.each_with_index.filter_map { |player, index| player[:name] if final_scores[index] == final_scores.max }
    lines << 'winner ' + winners.join(',')
    if highlight
      number, player, item = highlight
      lines << "highlight turn=#{number} player=#{player} play #{notation(item)} score=#{item.score}"
    end
    lines << position_summary(board)
    lines.concat(Board.display(board))
    @game_totals[:turns] += turn
    players.each { |player| %i[plays exchanges passes bingos].each { |key| @game_totals[key] += player[:stats][key] } }
    lines
  end

  def duplicate_game(job)
    _, name, seed = job.first.split
    random = Game::Minstd.new(seed.to_i)
    bag = Game.make_bag(@counts, random)
    board = Array.new(Board::SIZE) { Array.new(Board::SIZE, '.') }
    rack = Game.draw(bag, 7)
    players = job.drop(1).map { |line| line.split.drop(1) }
    totals = Array.new(players.size, 0)
    lines = ["DUPLICATE #{name} seed=#{seed.to_i} players=#{players.size}"]
    players.each_with_index { |(player, strategy), index| lines << "player #{index + 1} #{player} strategy=#{strategy}" }
    round, master_total, reason = 0, 0, 'stuck'
    loop do
      legal = legal_moves(board, rack)
      break if legal.empty?
      round += 1
      master = legal.first
      choices = players.map { |_, strategy| legal.min_by { |item| strategy_key(item, strategy) } }
      choices.each_with_index { |item, index| totals[index] += item.score }
      master_total += master.score
      picks = choices.map(&:score).join(',')
      lines << "round #{round} rack=#{collection(rack)} moves=#{legal.size} master #{notation(master)} score=#{master.score} picks=#{picks}"
      board = Scoring.apply(board, master.new_tiles)
      rack = master.leave + Game.draw(bag, 7 - master.leave.size)
      if rack.empty?
        reason = 'out'
        break
      end
    end
    suffix = reason == 'stuck' ? " rack=#{collection(rack)}" : ''
    lines << "end reason=#{reason} rounds=#{round}#{suffix}"
    lines << "master total=#{master_total}"
    players.each_with_index do |(player, _), index|
      percent = master_total >= 1 ? 100 * totals[index] / master_total : 0
      lines << "final #{player} total=#{totals[index]} percent=#{percent}"
    end
    winners = players.each_with_index.filter_map { |(player, _), index| player if totals[index] == totals.max }
    lines << 'winner ' + winners.join(',')
    lines << position_summary(board)
    lines.concat(Board.display(board))
    @game_totals[:rounds] += round
    lines
  end

  def process(jobs, dictionary_lines)
    move_blocks, validation_blocks, game_blocks = [dictionary_lines], [], []
    seen = Set.new
    jobs.each do |job|
      kind, name = job.first.split.first(2)
      destination, totals, key = case kind
                                 when 'TOPN' then [move_blocks, @topn_totals, :jobs]
                                 when 'VALIDATE' then [validation_blocks, @validation_totals, :jobs]
                                 else [game_blocks, @game_totals, kind == 'GAME' ? :games : :duplicates]
                                 end
      totals[key] += 1
      error = job_error(job, seen)
      seen.add(name)
      if error
        destination << ["#{kind} #{name}", "error #{error}"]
        totals[:errors] += 1
      else
        destination << case kind
                       when 'TOPN' then topn(job)
                       when 'VALIDATE' then validate(job)
                       when 'GAME' then ordinary_game(job)
                       else duplicate_game(job)
                       end
      end
    end
    [[move_blocks, @topn_totals, %i[jobs errors moves bingos]],
     [validation_blocks, @validation_totals, %i[jobs errors moves valid invalid loss]],
     [game_blocks, @game_totals, %i[games duplicates errors turns rounds plays exchanges passes bingos]]].each do |blocks, totals, keys|
      blocks << ['SUMMARY ' + keys.map { |key| "#{key}=#{totals[key]}" }.join(' ')]
    end
    [move_blocks, validation_blocks, game_blocks]
  end
end

if $PROGRAM_NAME == __FILE__
  values, counts, weights, trie, jobs, dictionary_lines = Scrabble.read_inputs
  reports = Scrabble.new(values, counts, weights, trie).process(jobs, dictionary_lines)
  FileUtils.mkdir_p('output')
  %w[moves.txt validation.txt game.txt].zip(reports).each do |filename, blocks|
    File.write(File.join('output', filename), blocks.map { |block| block.join("\n") }.join("\n\n") + "\n", encoding: 'US-ASCII')
  end
end
