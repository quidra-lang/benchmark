class CubeError < StandardError
end

class Cube
  FACES = %w[U R F D L B].freeze
  COLORS = %w[W R G Y O B].freeze
  LETTERS = 'UDFBLRMESudfblrxyz'
  CORNERS = %w[URF UFL ULB UBR DFR DLF DBL DRB].freeze
  EDGES = %w[UR UF UL UB DR DF DL DB FR FL BL BR].freeze
  CORNER_STICKERS = %w[U9,R1,F3 U7,F1,L3 U1,L1,B3 U3,B1,R3 D3,F9,R7 D1,L9,F7 D7,B9,L7 D9,R9,B7].freeze
  EDGE_STICKERS = %w[U6,R2 U8,F2 U4,L2 U2,B2 D6,R8 D2,F8 D4,L8 D8,B8 F6,R4 F4,L6 B6,L4 B4,R6].freeze
  NO_ARGS = %w[RESET SHOW STATE ISSOLVED HISTORY SOLUTION ANALYZE STAGE MACROS].freeze
  WORDS = { 'CHECK' => 1, 'LOAD' => 1, 'UNDO' => 1, 'REDO' => 1, 'SEARCH' => 1, 'WHERE' => 1, 'SAVE' => 1, 'RESTORE' => 1, 'SCRAMBLE' => 2 }.freeze
  SEQUENCES = %w[APPLY INVERT SIMPLIFY METRICS ORDER CYCLES UNROTATE UNTIL].freeze
  HEADS = %w[DEFINE MIRROR ROTATE].freeze
  def initialize
    @identity = (0...54).to_a
    @solved = COLORS.flat_map { |color| [color] * 9 }
    @state = @solved.dup
    @history = []
    @redo = []
    @macros = {}
    @saves = {}
    @moves = {}
    build_moves
    @rotations = []
    [[], [['x', 1]], [['x', 2]], [['x', 3]], [['z', 1]], [['z', 3]]].each do |prefix|
      [[], [['y', 1]], [['y', 2]], [['y', 3]]].each { |suffix| @rotations << prefix + suffix }
    end
    @rotation_effects = @rotations.map { |sequence| effect(sequence) }
    @positions = [CORNER_STICKERS.map { |group| group.split(',').map { |sticker| sticker_index(sticker) } },
                  EDGE_STICKERS.map { |group| group.split(',').map { |sticker| sticker_index(sticker) } },
                  FACES.map { |face| [index(face, 2, 2)] }]
    @names = [CORNERS, EDGES, FACES]
    @piece_colors = @positions.map { |positions| positions.map { |stickers| stickers.map { |i| @solved[i] } } }
  end
  def error(message)
    raise CubeError, "error: #{message}"
  end
  def index(face, row, col)
    FACES.index(face) * 9 + (row - 1) * 3 + col - 1
  end
  def sticker_index(word)
    FACES.index(word[0]) * 9 + word[1].to_i - 1
  end
  def compose(first, second)
    first.map { |destination| second[destination] }
  end
  def inverse(sequence)
    sequence.reverse.map { |letter, amount| [letter, 4 - amount] }
  end
  def permute(state, permutation)
    result = Array.new(54)
    permutation.each_with_index { |destination, source| result[destination] = state[source] }
    result
  end
  def effect(sequence)
    sequence.reduce(@identity) { |permutation, move| compose(permutation, @moves[move]) }
  end
  def build_moves
    %w[U R F D L B M E S].each do |letter|
      p = @identity.dup
      if FACES.include?(letter)
        (1..3).each { |i| (1..3).each { |j| p[index(letter, i, j)] = index(letter, j, 4 - i) } }
      end
      put = ->(a, i, j, b, k, l) { p[index(a, i, j)] = index(b, k, l) }
      (1..3).each do |i|
        case letter
        when 'U'
          %w[F L B R].each_with_index { |face, j| put.call(face, 1, i, %w[L B R F][j], 1, i) }
        when 'D'
          %w[F R B L].each_with_index { |face, j| put.call(face, 3, i, %w[R B L F][j], 3, i) }
        when 'R'
          put.call('F', i, 3, 'U', i, 3)
          put.call('U', i, 3, 'B', 4 - i, 1)
          put.call('B', i, 1, 'D', 4 - i, 3)
          put.call('D', i, 3, 'F', i, 3)
        when 'L'
          put.call('U', i, 1, 'F', i, 1)
          put.call('F', i, 1, 'D', i, 1)
          put.call('D', i, 1, 'B', 4 - i, 3)
          put.call('B', i, 3, 'U', 4 - i, 1)
        when 'F'
          put.call('U', 3, i, 'R', i, 1)
          put.call('R', i, 1, 'D', 1, 4 - i)
          put.call('D', 1, i, 'L', i, 3)
          put.call('L', i, 3, 'U', 3, 4 - i)
        when 'B'
          put.call('U', 1, i, 'L', 4 - i, 1)
          put.call('L', i, 1, 'D', 3, i)
          put.call('D', 3, i, 'R', 4 - i, 3)
          put.call('R', i, 3, 'U', 1, i)
        when 'M'
          put.call('U', i, 2, 'F', i, 2)
          put.call('F', i, 2, 'D', i, 2)
          put.call('D', i, 2, 'B', 4 - i, 2)
          put.call('B', i, 2, 'U', 4 - i, 2)
        when 'E'
          %w[F R B L].each_with_index { |face, j| put.call(face, 2, i, %w[R B L F][j], 2, i) }
        when 'S'
          put.call('U', 2, i, 'R', i, 2)
          put.call('R', i, 2, 'D', 2, 4 - i)
          put.call('D', 2, i, 'L', i, 2)
          put.call('L', i, 2, 'U', 2, 4 - i)
        end
      end
      (1..3).each { |amount| @moves[[letter, amount]] = amount.times.reduce(@identity) { |current, _| compose(current, p) } }
    end
    { 'r' => [['R', 1], ['M', 3]], 'l' => [['L', 1], ['M', 1]], 'u' => [['U', 1], ['E', 3]],
      'd' => [['D', 1], ['E', 1]], 'f' => [['F', 1], ['S', 1]], 'b' => [['B', 1], ['S', 3]],
      'x' => [['R', 1], ['M', 3], ['L', 3]], 'y' => [['U', 1], ['E', 3], ['D', 3]], 'z' => [['F', 1], ['S', 1], ['B', 3]] }.each do |letter, sequence|
      p = effect(sequence)
      (1..3).each { |amount| @moves[[letter, amount]] = amount.times.reduce(@identity) { |current, _| compose(current, p) } }
    end
  end
  def parse(sequence, base, line_length)
    position = 0
    syntax = -> { error("syntax at #{[base + position + 1, line_length + 1].min}") }
    spaces = -> { position += 1 while sequence[position] == ' ' }
    power = lambda do |moves|
      count = 1
      if sequence[position]&.match?(/[1-9]/)
        count = sequence[position].to_i
        position += 1
        if sequence[position]&.match?(/[0-9]/)
          count = 10 * count + sequence[position].to_i
          position += 1
        end
      end
      moves *= count
      if sequence[position] == "'"
        position += 1
        moves = inverse(moves)
      end
      moves
    end
    read = nil
    read = lambda do
      output = []
      loop do
        spaces.call
        char = sequence[position]
        if char && LETTERS.include?(char)
          position += 1
          amount = 1
          if ['2', "'"].include?(sequence[position])
            amount = sequence[position] == '2' ? 2 : 3
            position += 1
          end
          output << [char, amount]
        elsif char == '('
          position += 1
          moves = read.call
          spaces.call
          syntax.call unless sequence[position] == ')'
          position += 1
          output.concat(power.call(moves))
        elsif char == '['
          position += 1
          a = read.call
          spaces.call
          delimiter = sequence[position]
          syntax.call unless [',', ':'].include?(delimiter)
          position += 1
          b = read.call
          spaces.call
          syntax.call unless sequence[position] == ']'
          position += 1
          moves = a + b + inverse(a)
          moves += inverse(b) if delimiter == ','
          output.concat(power.call(moves))
        elsif char == '{'
          position += 1
          start = position
          position += 1 while sequence[position]&.match?(/[a-z]/)
          name = sequence[start...position]
          syntax.call if name.empty? || sequence[position] != '}'
          error("undefined #{name}") unless @macros.key?(name)
          position += 1
          output.concat(power.call(@macros[name].dup))
        else
          break
        end
      end
      output
    end
    moves = read.call
    spaces.call
    syntax.call if position < sequence.length
    error('too long') if moves.length > 500
    moves
  end
  def notation(sequence)
    ([sequence.length.to_s] + sequence.map { |letter, amount| letter + (amount == 1 ? '' : amount == 2 ? '2' : "'") }).join(' ')
  end
  def move_words(sequence)
    sequence.map { |letter, amount| letter + (amount == 1 ? '' : amount == 2 ? '2' : "'") }.join(' ')
  end
  def axis(letter)
    return 'x' if 'RLMrlx'.include?(letter)
    return 'y' if 'UDEudy'.include?(letter)
    'z'
  end
  def simplify(sequence)
    loop do
      output = []
      position = 0
      while position < sequence.length
        current_axis = axis(sequence[position][0])
        amounts = {}
        while position < sequence.length && axis(sequence[position][0]) == current_axis
          letter, amount = sequence[position]
          amounts[letter] = (amounts.fetch(letter, 0) + amount) % 4
          position += 1
        end
        amounts.each { |letter, amount| output << [letter, amount] unless amount == 0 }
      end
      return output if output == sequence
      sequence = output
    end
  end
  def solved?(state)
    (0...6).all? { |face| state[face * 9, 9].all? { |color| color == state[face * 9 + 4] } }
  end
  def normalize(state)
    @rotation_effects.each_with_index do |permutation, index|
      rotated = permute(state, permutation)
      return [index, rotated] if (0...6).all? { |face| rotated[face * 9 + 4] == COLORS[face] }
    end
    nil
  end
  def identify(state, kind)
    @positions[kind].map do |stickers|
      colors = stickers.map { |i| state[i] }
      found = nil
      @piece_colors[kind].each_with_index do |piece, index|
        (0...piece.length).each { |twist| found = [index, twist] if colors.rotate(twist) == piece }
      end
      found
    end
  end
  def invalid(state)
    return "length #{state.length}" unless state.length == 54
    bad = state.index { |color| !COLORS.include?(color) }
    return "char #{bad + 1}" if bad
    COLORS.each { |color| return "count #{color} #{state.count(color)}" unless state.count(color) == 9 }
    normalized = normalize(state)
    return 'centers' unless normalized
    original = [identify(state, 0), identify(state, 1)]
    original.each_with_index do |pieces, kind|
      bad = pieces.index(nil)
      return "#{kind == 0 ? 'corner' : 'edge'} #{@names[kind][bad]}" if bad
    end
    original.each_with_index do |pieces, kind|
      @names[kind].each_with_index { |name, index| return "missing #{name}" unless pieces.any? { |piece| piece[0] == index } }
    end
    corners = identify(normalized[1], 0)
    edges = identify(normalized[1], 1)
    return 'twist' unless corners.sum { |piece| piece[1] } % 3 == 0
    return 'flip' unless edges.sum { |piece| piece[1] } % 2 == 0
    parity = ->(pieces) { pieces.each_index.sum { |i| ((i + 1)...pieces.length).count { |j| pieces[i][0] > pieces[j][0] } } % 2 }
    return 'parity' unless parity.call(corners) == parity.call(edges)
    nil
  end
  def cycles(state, kind)
    pieces = identify(state, kind)
    destination = Array.new(pieces.length)
    orientation = Array.new(pieces.length)
    pieces.each_with_index do |(piece, twist), index|
      destination[piece] = index
      orientation[piece] = twist
    end
    seen = []
    output = []
    pieces.each_index do |start|
      next if seen.include?(start)
      cycle = []
      current = start
      loop do
        cycle << current
        seen << current
        current = destination[current]
        break if current == start
      end
      sum = cycle.sum { |piece| orientation[piece] }
      mark = kind == 0 ? ['', '+', '-'][sum % 3] : kind == 1 && sum.odd? ? '+' : ''
      output << '(' + cycle.map { |piece| @names[kind][piece] }.join(' ') + ')' + mark if cycle.length >= 2 || !mark.empty?
    end
    output.empty? ? 'none' : output.join(' ')
  end
  def order(permutation)
    seen = []
    result = 1
    permutation.each_index do |start|
      next if seen.include?(start)
      current = start
      length = 0
      loop do
        seen << current
        length += 1
        current = permutation[current]
        break if current == start
      end
      result = result.lcm(length)
    end
    result
  end
  def converted(move, rotation)
    inverse_rotation = Array.new(54)
    rotation.each_with_index { |destination, source| inverse_rotation[destination] = source }
    target = compose(compose(rotation, @moves[move]), inverse_rotation)
    @moves.find { |_, permutation| permutation == target }[0]
  end
  def unrotate(sequence)
    replacements = { 'M' => [['R', 1], ['L', 3], ['x', 3]], 'E' => [['U', 1], ['D', 3], ['y', 3]], 'S' => [['F', 3], ['B', 1], ['z', 1]],
                     'r' => [['L', 1], ['x', 1]], 'l' => [['R', 1], ['x', 3]], 'u' => [['D', 1], ['y', 1]], 'd' => [['U', 1], ['y', 3]],
                     'f' => [['B', 1], ['z', 1]], 'b' => [['F', 1], ['z', 3]] }
    expanded = sequence.flat_map do |letter, amount|
      replacements.key?(letter) ? replacements[letter].map { |name, count| [name, count * amount % 4] } : [[letter, amount]]
    end
    rotation = @identity
    output = []
    expanded.each do |move|
      if 'xyz'.include?(move[0])
        rotation = compose(rotation, @moves[move])
      else
        output << converted(move, rotation)
      end
    end
    output + @rotations[@rotation_effects.index(rotation)]
  end
  def search(depth)
    candidates = FACES.flat_map { |face| (1..3).map { |amount| [face, amount] } }
    visit = nil
    visit = lambda do |state, left, previous|
      return [] if solved?(state)
      return nil if left == 0
      candidates.each do |move|
        face = move[0]
        next if face == previous || [['D', 'U'], ['L', 'R'], ['B', 'F']].include?([previous, face])
        tail = visit.call(permute(state, @moves[move]), left - 1, face)
        return [move] + tail if tail
      end
      nil
    end
    (0..depth).each do |limit|
      found = visit.call(@state, limit, nil)
      return found if found
    end
    nil
  end
  def command(line)
    command, argument = line.split(' ', 2)
    error("unknown command #{command}") unless (NO_ARGS + WORDS.keys + SEQUENCES + HEADS).include?(command)
    words = argument ? argument.split(' ') : []
    error('bad arguments') if NO_ARGS.include?(command) && argument
    error('bad arguments') if WORDS.key?(command) && words.length != WORDS[command]
    if %w[UNDO REDO SEARCH SCRAMBLE].include?(command)
      error('bad arguments') unless words.all? { |word| word.match?(/\A(?:0|[1-9][0-9]{0,9})\z/) }
    end
    if %w[SAVE RESTORE].include?(command)
      error('bad arguments') unless words[0].match?(/\A[a-z]{1,8}\z/)
    end
    if HEADS.include?(command)
      error('bad arguments') unless argument
      head, sequence = argument.split(' ', 2)
      valid = command == 'DEFINE' ? head.match?(/\A[a-z]{1,8}\z/) : command == 'MIRROR' ? %w[LR UD FB].include?(head) : head.match?(/\A[xyz](?:2|')?\z/)
      error('bad arguments') unless valid
      moves = parse(sequence || '', command.length + head.length + 2, line.length)
    elsif SEQUENCES.include?(command)
      moves = parse(argument || '', command.length + 1, line.length)
    end
    error('bad value') if %w[UNDO REDO].include?(command) && words[0].to_i < 1
    error('bad value') if command == 'SEARCH' && words[0].to_i > 4
    error('bad value') if command == 'SCRAMBLE' && (!words[0].to_i.between?(1, 50) || !words[1].to_i.between?(1, 2147483646))
    error("unknown piece #{words[0]}") if command == 'WHERE' && !(CORNERS + EDGES).include?(words[0])
    case command
    when 'RESET'
      @state = @solved.dup
      @history = []
      @redo = []
      puts 'reset'
    when 'SHOW'
      %w[U LFRB D].each do |faces|
        (1..3).each { |row| puts (faces.length == 1 ? '      ' : '') + faces.chars.flat_map { |face| (1..3).map { |col| @state[index(face, row, col)] } }.join(' ') }
      end
    when 'STATE' then puts 'state ' + @state.join
    when 'ISSOLVED'
      count = @state.each_index.count { |i| @state[i] != @state[i / 9 * 9 + 4] }
      puts(count == 0 ? 'solved' : "unsolved #{count}")
    when 'HISTORY' then puts 'history ' + notation(@history)
    when 'SOLUTION' then puts 'solution ' + notation(simplify(inverse(@history)))
    when 'ANALYZE'
      rotation, state = normalize(@state)
      puts 'rotation ' + (rotation == 0 ? 'none' : move_words(@rotations[rotation]))
      puts 'corners ' + cycles(state, 0)
      puts 'edges ' + cycles(state, 1)
    when 'STAGE'
      _, state = normalize(@state)
      corners = identify(state, 0)
      edges = identify(state, 1)
      cross = (4..7).count { |i| edges[i] == [i, 0] }
      slots = (4..7).count { |i| corners[i] == [i, 0] && edges[i + 4] == [i + 4, 0] }
      top = state[0, 9].count('W')
      stage = solved?(state) ? 'solved' : cross == 4 && slots == 4 && top == 9 ? 'oll' : cross == 4 && slots == 4 ? 'f2l' : cross == 4 ? 'cross' : 'none'
      puts "stage #{stage} cross #{cross} slots #{slots} top #{top}"
    when 'MACROS'
      puts "macros #{@macros.length}"
      @macros.keys.sort.each { |name| puts "macro #{name} #{notation(@macros[name])}" }
    when 'CHECK', 'LOAD'
      state = words[0].chars
      reason = invalid(state)
      if command == 'CHECK'
        puts(reason ? 'invalid ' + reason : 'valid')
      else
        error('invalid ' + reason) if reason
        @state = state
        @history = []
        @redo = []
        puts 'loaded'
      end
    when 'UNDO', 'REDO'
      source = command == 'UNDO' ? @history : @redo
      error(command == 'UNDO' ? 'nothing to undo' : 'nothing to redo') if source.empty?
      count = [words[0].to_i, source.length].min
      count.times do
        move = source.pop
        @state = permute(@state, @moves[command == 'UNDO' ? [move[0], 4 - move[1]] : move])
        (command == 'UNDO' ? @redo : @history) << move
      end
      puts "#{command == 'UNDO' ? 'undone' : 'redone'} #{count}"
    when 'SEARCH'
      found = search(words[0].to_i)
      puts(found ? 'found ' + notation(found) : 'not found')
    when 'WHERE'
      _, state = normalize(@state)
      kind = CORNERS.include?(words[0]) ? 0 : 1
      wanted = @names[kind].index(words[0])
      pieces = identify(state, kind)
      position = pieces.index { |piece| piece[0] == wanted }
      puts "#{words[0]} at #{@names[kind][position]} #{kind == 0 ? 'twist' : 'flip'} #{pieces[position][1]}"
    when 'SAVE'
      @saves[words[0]] = [@state.dup, @history.map(&:dup)]
      puts "saved #{words[0]}"
    when 'RESTORE'
      error("no save #{words[0]}") unless @saves.key?(words[0])
      @state, @history = @saves[words[0]].map { |part| part.map { |item| item.is_a?(Array) ? item.dup : item } }
      @redo = []
      puts "restored #{words[0]}"
    when 'SCRAMBLE', 'APPLY'
      if command == 'SCRAMBLE'
        moves = []
        random = words[1].to_i
        words[0].to_i.times do
          usable = FACES.reject do |face|
            (!moves.empty? && face == moves[-1][0]) || (moves.length >= 2 && axis(moves[-1][0]) == axis(moves[-2][0]) && axis(face) == axis(moves[-1][0]))
          end
          random = random * 48271 % 2147483647
          face = usable[random % usable.length]
          random = random * 48271 % 2147483647
          moves << [face, [1, 3, 2][random % 3]]
        end
      end
      @state = permute(@state, effect(moves))
      @history.concat(moves)
      @redo = []
      puts(command == 'APPLY' ? "applied #{moves.length}" : 'scramble ' + move_words(moves))
    when 'INVERT' then puts 'inverse ' + notation(inverse(moves))
    when 'SIMPLIFY' then puts 'simplified ' + notation(simplify(moves))
    when 'METRICS'
      htm = qtm = stm = 0
      moves.each do |letter, amount|
        next if 'xyz'.include?(letter)
        weight = 'MES'.include?(letter) ? 2 : 1
        htm += weight
        qtm += weight * (amount == 2 ? 2 : 1)
        stm += 1
      end
      puts "metrics htm #{htm} qtm #{qtm} stm #{stm} etm #{moves.length}"
    when 'ORDER' then puts "order #{order(effect(moves))}"
    when 'CYCLES'
      state = permute(@solved, effect(moves))
      %w[corners edges centers].each_with_index { |kind, i| puts kind + ' ' + cycles(state, i) }
    when 'UNROTATE' then puts 'unrotated ' + notation(unrotate(moves))
    when 'UNTIL'
      permutation = effect(moves)
      state = @state
      found = nil
      (1..order(permutation)).each do |count|
        state = permute(state, permutation)
        if solved?(state)
          found = count
          break
        end
      end
      puts "until #{found || 'never'}"
    when 'DEFINE'
      @macros[head] = moves
      puts "defined #{head} #{moves.length}"
    when 'MIRROR'
      mirror_axis = { 'LR' => 'x', 'UD' => 'y', 'FB' => 'z' }[head]
      opposites = 'RLUDFBrludfb'.chars.zip('LRDUBFlrdubf'.chars).to_h
      transformed = moves.map do |letter, amount|
        if axis(letter) != mirror_axis
          [letter, 4 - amount]
        elsif 'MESxyz'.include?(letter)
          [letter, amount]
        else
          [opposites[letter], 4 - amount]
        end
      end
      puts 'mirror ' + notation(transformed)
    when 'ROTATE'
      amount = head.length == 1 ? 1 : head[1] == '2' ? 2 : 3
      rotation = @moves[[head[0], amount]]
      puts 'rotated ' + notation(moves.map { |move| converted(move, rotation) })
    end
  rescue CubeError => exception
    puts exception.message
  end
  def run
    count = STDIN.readline.to_i
    count.times { command(STDIN.readline.chomp("\n").delete_suffix("\r")) }
  end
end

Cube.new.run
