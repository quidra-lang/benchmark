require 'set'
require_relative 'bitstream'
require_relative 'reed_solomon'
require_relative 'matrix'
require_relative 'masking'
require_relative 'render'

LEVELS = %w[L M Q H].freeze
MODES = %w[NUMERIC ALPHANUMERIC BYTE].freeze
INDICATORS = { 'NUMERIC' => 1, 'ALPHANUMERIC' => 2, 'BYTE' => 4 }.freeze
ERROR_KINDS = %w[level mode version mask text charset capacity].freeze

def count_width(mode, version)
  (version == 10 ? [12, 11, 16] : [10, 9, 8])[MODES.index(mode)]
end

def data_width(mode, count)
  case mode
  when 'NUMERIC' then 10 * (count / 3) + [0, 4, 7][count % 3]
  when 'ALPHANUMERIC' then 11 * (count / 2) + 6 * (count % 2)
  else 8 * count
  end
end

def encodable?(mode, character)
  case mode
  when 'NUMERIC' then character.between?('0', '9')
  when 'ALPHANUMERIC' then Bitstream::VALUES.key?(character)
  else character.ord.between?(32, 126)
  end
end

def segment_width(mode, text, version) = 4 + count_width(mode, version) + data_width(mode, text.length)

def groups(mode, text)
  step = { 'NUMERIC' => 3, 'ALPHANUMERIC' => 2, 'BYTE' => 1 }.fetch(mode)
  (0...text.length).step(step).map do |start|
    characters = text[start, step]
    case mode
    when 'NUMERIC'
      value, width = characters.to_i, [0, 4, 7, 10][characters.length]
    when 'ALPHANUMERIC'
      value, width = Bitstream::VALUES[characters[0]], 6
      value, width = 45 * value + Bitstream::VALUES[characters[1]], 11 if characters.length == 2
    else
      value, width = characters.ord, 8
    end
    [value, width, characters]
  end
end

def mixed_segments(text, version)
  invalid = MODES.to_h { |mode| [mode, [0]] }
  text.each_char do |character|
    MODES.each { |mode| invalid[mode] << invalid[mode].last + (encodable?(mode, character) ? 0 : 1) }
  end
  costs, choices = Array.new(text.length + 1, 0), Array.new(text.length + 1)
  (1..text.length).each do |finish|
    best = nil
    finish.times do |start|
      MODES.each do |mode|
        next unless invalid[mode][finish] == invalid[mode][start]
        cost = costs[start] + 4 + count_width(mode, version) + data_width(mode, finish - start)
        if best.nil? || cost < best
          best = cost
          choices[finish] = [start, mode]
        end
      end
    end
    costs[finish] = best
  end
  segments, finish = [], text.length
  until finish.zero?
    start, mode = choices[finish]
    segments << [mode, text[start...finish]]
    finish = start
  end
  [segments.reverse, costs.last]
end

def assemble_bits(segments, version)
  writer, lines = Bitstream::Writer.new, []
  segments.each do |mode, text|
    indicator, width = INDICATORS[mode], count_width(mode, version)
    writer.write(indicator, 4)
    writer.write(text.length, width)
    lines << "segment #{mode} indicator #{Bitstream.binary(indicator, 4)} count #{text.length} #{Bitstream.binary(text.length, width)}"
    groups(mode, text).each do |value, group_width, characters|
      writer.write(value, group_width)
      lines << "group #{value} #{Bitstream.binary(value, group_width)} \"#{characters}\""
    end
  end
  [writer.bits, lines]
end

def pad_bits(bits, capacity)
  terminator = [4, capacity - bits.length].min
  padded = bits + '0' * terminator
  zero_fill = -padded.length % 8
  padded += '0' * zero_fill
  pad_count = (capacity - padded.length) / 8
  pad_count.times { |index| padded << (index.even? ? '11101100' : '00010001') }
  [padded, [terminator, zero_fill, pad_count]]
end

class BlockLayout
  attr_reader :degree, :lengths, :count, :data, :capacity, :total, :placement

  def initialize(degree, first_count, first_size, second_count, second_size)
    @degree = degree
    @lengths = Array.new(first_count, first_size) + Array.new(second_count, second_size)
    @count, @data = @lengths.length, @lengths.sum
    @capacity, @total = 8 * @data, @data + degree * @count
    @placement = []
    @lengths.max.times do |position|
      @lengths.each_with_index { |length, block| @placement << [block, position] if position < length }
    end
    degree.times { |offset| @lengths.each_with_index { |length, block| @placement << [block, length + offset] } }
  end

  def encode(data)
    start = 0
    blocks = @lengths.map do |length|
      words = data[start, length]
      start += length
      words + ReedSolomon.parity(words, @degree)
    end
    [blocks, @placement.map { |block, position| blocks[block][position] }]
  end

  def deinterleave(words)
    blocks = @lengths.map { |length| Array.new(length + @degree, 0) }
    words.zip(@placement).each { |value, (block, position)| blocks[block][position] = value }
    blocks
  end
end

class Geometry
  attr_reader :size, :symbol, :areas, :order, :indices, :data_modules, :function_modules

  def initialize(version, alignments)
    @size = 17 + 4 * version
    @symbol, @areas = QRMatrix.function_matrix(version, alignments)
    @order = QRMatrix.reading_order(@areas)
    @indices = @order.each_with_index.to_h
    @data_modules = @order.length
    @function_modules = @size * @size - @data_modules
  end
end

class Request
  attr_reader :id, :level_token, :mode_token, :version_token, :mask_token, :text,
              :mode, :version, :level, :segments, :bit_count, :boosted

  def initialize(fields, text)
    @id, @level_token, @mode_token, @version_token, @mask_token = fields
    @text, @splits = text, {}
  end

  def split(version)
    category = version == 10 ? 10 : 1
    @splits[category] ||= @mode == 'MIXED' ? mixed_segments(@text, version) : [[[@mode, @text]], segment_width(@mode, @text, version)]
  end

  def prepare(codec)
    return "level #{@level_token}" unless (LEVELS + LEVELS.map { |level| level + '+' }).include?(@level_token)
    return "mode #{@mode_token}" unless (MODES + %w[AUTO MIXED]).include?(@mode_token)
    return "version #{@version_token}" unless (['AUTO'] + (1..10).map(&:to_s)).include?(@version_token)
    return "mask #{@mask_token}" unless (['AUTO'] + (0..7).map(&:to_s)).include?(@mask_token)
    return 'text' if @text.empty?
    if %w[NUMERIC ALPHANUMERIC].include?(@mode_token)
      position = @text.chars.index { |character| !encodable?(@mode_token, character) }
      return "charset position #{position}" if position
    end
    @mode = @mode_token
    @mode = MODES.find { |mode| @text.each_char.all? { |character| encodable?(mode, character) } } if @mode == 'AUTO'
    base = @level_token[0]
    candidates = @version_token == 'AUTO' ? (1..10) : [@version_token.to_i]
    bits, capacity = nil, nil
    candidates.each do |version|
      bits, capacity = split(version).last, codec.tables[[version, base]].capacity
      if bits <= capacity
        @version = version
        break
      end
    end
    return "capacity bits #{bits} capacity #{capacity}" unless @version
    @segments, @bit_count = split(@version)
    @level = base
    if @level_token.end_with?('+')
      LEVELS.drop(LEVELS.index(base)).each do |level|
        @level = level if @bit_count <= codec.tables[[@version, level]].capacity
      end
    end
    @boosted = @level != base
    nil
  end
end

def read_inputs
  requests = File.readlines('input/requests.txt', chomp: true).map do |line|
    header, text = line.split(':', 2)
    Request.new(header.split(' '), text || '')
  end
  params = File.readlines('input/params.txt').to_h { |line| name, value = line.split; [name, value.to_i] }
  tables, alignments = {}, {}
  File.foreach('input/tables.txt') do |line|
    fields = line.split
    version = fields[1].to_i
    if fields.first == 'block'
      tables[[version, fields[2]]] = BlockLayout.new(*fields.drop(3).map(&:to_i))
    else
      alignments[version] = fields.drop(2).map(&:to_i)
    end
  end
  damage = Hash.new { |hash, id| hash[id] = [] }
  File.foreach('input/damage.txt') do |line|
    id, operation, *arguments = line.split
    entry = case operation
            when 'flip' then [operation, *arguments.map(&:to_i)]
            when 'fill' then [operation, *arguments.first(4).map(&:to_i), arguments[4] == 'dark' ? 1 : 0]
            else [operation]
            end
    damage[id] << entry
  end
  lines = File.readlines('input/scans.txt', chomp: true)
  scans, index = [], 0
  while index < lines.length
    name = lines[index].split.last
    size = lines[index + 1].length
    symbol = lines[index + 1, size].map { |line| line.chars.map { |c| c == '#' ? 1 : 0 } }
    scans << [name, symbol]
    index += size + 1
  end
  [requests, params, tables, alignments, damage, scans]
end

class Encoding
  attr_reader :request, :layout, :block_layout, :raw_bits, :trace, :padding,
              :blocks, :codewords, :penalties, :mask, :symbol, :dark

  def initialize(request, codec)
    @request, @layout = request, codec.geometry(request.version)
    @block_layout = codec.tables[[request.version, request.level]]
    @raw_bits, @trace = assemble_bits(request.segments, request.version)
    padded, @padding = pad_bits(@raw_bits, @block_layout.capacity)
    @blocks, @codewords = @block_layout.encode(Bitstream.to_codewords(padded))
    unmasked = @layout.symbol.map(&:dup)
    Bitstream.from_codewords(@codewords).chars.zip(@layout.order).each { |bit, (x, y)| unmasked[y][x] = bit.to_i }
    @penalties = []
    candidates = (0..7).map do |mask|
      symbol = Masking.apply(unmasked, @layout.order, mask)
      info = QRMatrix.format_information(request.level, mask)
      QRMatrix.format_positions(@layout.size).each { |positions| QRMatrix.write_value(symbol, positions, info) }
      @penalties << Masking.penalties(symbol)
      symbol
    end
    @mask = request.mask_token == 'AUTO' ? (0..7).min_by { |mask| @penalties[mask].sum } : request.mask_token.to_i
    @symbol = candidates[@mask]
    @dark = @symbol.sum(&:sum)
  end
end

def codes_lines(encoding, codec)
  request, layout, blocks = encoding.request, encoding.layout, encoding.block_layout
  version, level = request.version, request.level
  lines = ["symbol version #{version} level #{level} mask #{encoding.mask} size #{layout.size}"]
  lines << "segments #{request.segments.length} " + request.segments.map { |mode, text| "#{mode}:#{text.length}" }.join(' ')
  alternatives = MODES.map do |mode|
    possible = request.text.each_char.all? { |character| encodable?(mode, character) }
    "#{mode} #{possible ? segment_width(mode, request.text, version) : '-'}"
  end
  mixed_bits = request.mode == 'MIXED' ? request.bit_count : mixed_segments(request.text, version).last
  lines << "bits data #{request.bit_count} capacity #{blocks.capacity} alternatives #{alternatives.join(' ')} MIXED #{mixed_bits}"
  fits = LEVELS.map do |candidate_level|
    fitting = (1..10).find { |v| request.split(v).last <= codec.tables[[v, candidate_level]].capacity } || '-'
    "#{candidate_level} #{fitting}"
  end
  lines << 'fits ' + fits.join(' ')
  lines << "modules function #{layout.function_modules} data #{layout.data_modules} remainder #{layout.data_modules - 8 * blocks.total} dark #{encoding.dark}"
  info = QRMatrix.format_information(level, encoding.mask)
  version_text = version >= 7 ? Bitstream.binary(QRMatrix.version_information(version), 18) : 'none'
  lines << "format #{Bitstream.binary(info, 15)} version #{version_text}"
  encoding.penalties.each_with_index do |(n1, n2, n3, n4), mask|
    lines << "penalty #{mask} n1 #{n1} n2 #{n2} n3 #{n3} n4 #{n4} total #{n1 + n2 + n3 + n4}"
  end
  lines.concat(Render.symbol_lines(encoding.symbol))
end

def codeword_lines(encoding)
  request, layout = encoding.request, encoding.block_layout
  lines = ["request #{request.id} version #{request.version} level #{request.level} blocks #{layout.count} data #{layout.data} ec_per_block #{layout.degree} total #{layout.total}"]
  encoding.blocks.zip(layout.lengths).each_with_index do |(words, length), block|
    lines << "block #{block} data #{Bitstream.hexadecimal(words.first(length))}"
    lines << "block #{block} ec #{Bitstream.hexadecimal(words.drop(length))}"
  end
  lines << 'interleaved ' + Bitstream.hexadecimal(encoding.codewords)
end

def bitstream_lines(encoding)
  request = encoding.request
  lines = ["request #{request.id} version #{request.version} bits #{request.bit_count} capacity #{encoding.block_layout.capacity}"]
  lines.concat(encoding.trace)
  terminator, zero_fill, pad_count = encoding.padding
  lines << "terminator #{terminator} zero_fill #{zero_fill} pad_bytes #{pad_count}"
end

def read_image(path)
  lines = File.readlines(path, chomp: true)
  width, height = lines[1].split.map(&:to_i)
  pixels = lines[2, height].map { |line| line.chars.map(&:to_i) }
  dark = pixels.each_with_index.flat_map { |row, y| row.each_index.filter_map { |x| [x, y] if row[x] == 1 } }
  left, right, top = dark.map(&:first).min, dark.map(&:first).max, dark.map(&:last).min
  run = 0
  run += 1 while left + run < width && pixels[top][left + run] == 1
  unit = run / 7
  size = (right - left + 1) / unit
  symbol = Array.new(size) { |y| Array.new(size) { |x| pixels[top + unit * y][left + unit * x] } }
  well_formed = true
  height.times do |y|
    width.times do |x|
      inside = x >= left && x < left + unit * size && y >= top && y < top + unit * size
      expected = inside ? symbol[(y - top) / unit][(x - left) / unit] : 0
      well_formed = false unless pixels[y][x] == expected
    end
  end
  [symbol, "image #{width} #{height} quiet #{left / unit} scale #{unit} size #{size} #{well_formed ? 'ok' : 'bad'}"]
end

def rotate(symbol) = symbol.transpose.map(&:reverse)

def finder_rotation(symbol)
  size = symbol.length
  corners = [[size - 7, size - 7], [size - 7, 0], [0, 0], [0, size - 7]]
  scores = corners.map do |left, top|
    score = 0
    7.times do |y|
      7.times do |x|
        expected = [(x - 3).abs, (y - 3).abs].max == 2 ? 0 : 1
        score += 1 if symbol[top + y][left + x] == expected
      end
    end
    score
  end
  (0..3).min_by { |index| scores[index] }
end

class Attempt
  attr_accessor :lines, :text, :blocks
  def initialize
    @lines, @blocks, @text = [], [], nil
  end
end

def read_segment(reader, mode, count)
  characters = +''
  until count.zero?
    case mode
    when 'NUMERIC'
      group_size = [3, count].min
      value = reader.read([0, 4, 7, 10][group_size])
      return nil if value >= 10**group_size
      characters << value.to_s.rjust(group_size, '0')
    when 'ALPHANUMERIC'
      group_size = [2, count].min
      value = reader.read(group_size == 2 ? 11 : 6)
      return nil if value >= (group_size == 2 ? 2025 : 45)
      characters << Bitstream::ALPHANUMERIC[value / 45] if group_size == 2
      characters << Bitstream::ALPHANUMERIC[value % 45]
    else
      group_size = 1
      value = reader.read(8)
      return nil unless value.between?(32, 126)
      characters << value.chr
    end
    count -= group_size
  end
  characters
end

def parse_data(attempt, bits, version)
  reader, text, finish = Bitstream::Reader.new(bits), +'', 0
  modes = INDICATORS.invert
  while reader.remaining >= 4
    indicator = reader.read(4)
    break if indicator.zero?
    unless modes.key?(indicator)
      attempt.lines << "parse failed indicator #{Bitstream.binary(indicator, 4)}"
      return
    end
    mode = modes[indicator]
    width = count_width(mode, version)
    if reader.remaining < width
      attempt.lines << "parse failed length #{mode}"
      return
    end
    count = reader.read(width)
    if reader.remaining < data_width(mode, count)
      attempt.lines << "parse failed length #{mode}"
      return
    end
    segment = read_segment(reader, mode, count)
    if segment.nil?
      attempt.lines << "parse failed value #{mode}"
      return
    end
    text << segment
    attempt.lines << "segment #{mode} #{count}"
    finish = reader.position
  end
  expected = pad_bits(bits[0, finish], bits.length).first
  attempt.lines << 'padding ' + (expected == bits ? 'ok' : 'bad')
  attempt.text = text
  attempt.lines << "text \"#{text}\""
end

class Codec
  attr_reader :tables, :alignments

  def initialize(tables, alignments)
    @tables, @alignments, @geometries = tables, alignments, {}
    @formats = LEVELS.flat_map { |level| (0..7).map { |mask| [QRMatrix.format_information(level, mask), level, mask] } }
    @versions = (7..40).map { |version| [QRMatrix.version_information(version), version] }
  end

  def geometry(version) = @geometries[version] ||= Geometry.new(version, @alignments[version])

  def information(symbol, positions, candidates)
    values = positions.map { |set| QRMatrix.read_value(symbol, set) }
    nearest = values.map { |value| candidates.min_by { |candidate| (value ^ candidate.first).digits(2).sum } }
    distances = values.zip(nearest).map { |value, candidate| (value ^ candidate.first).digits(2).sum }
    chosen = nearest[distances[1] < distances[0] ? 1 : 0]
    [values, distances, chosen]
  end

  def attempt(symbol)
    result = Attempt.new
    size = symbol.length
    version = (size - 17) / 4
    values, distances, chosen = information(symbol, QRMatrix.format_positions(size), @formats)
    prefix = "format #{values.map { |v| Bitstream.binary(v, 15) }.join(' ')} distance #{distances.join(' ')}"
    if distances.min > 3
      result.lines << prefix + ' unreadable'
      return result
    end
    _, level, mask = chosen
    result.lines << "#{prefix} level #{level} mask #{mask}"
    if version >= 7
      values, distances, chosen = information(symbol, QRMatrix.version_positions(size), @versions)
      prefix = "version #{values.map { |v| Bitstream.binary(v, 18) }.join(' ')} distance #{distances.join(' ')}"
      if distances.min > 3
        result.lines << prefix + ' unreadable'
        return result
      end
      result.lines << "#{prefix} decoded #{chosen[1]}"
      return result unless chosen[1] == version
    end
    geometry = geometry(version)
    layout = @tables[[version, level]]
    unmasked = Masking.apply(symbol, geometry.order, mask)
    bits = geometry.order.first(8 * layout.total).map { |x, y| unmasked[y][x] }.join
    blocks = layout.deinterleave(Bitstream.to_codewords(bits))
    corrected_blocks, failed = [], false
    blocks.each_with_index do |received, block|
      syndromes, corrected, positions = ReedSolomon.correct(received, layout.degree)
      prefix = "block #{block} syndromes #{Bitstream.hexadecimal(syndromes)}"
      if corrected.nil?
        status = 'failed'
        result.lines << prefix + ' failed'
        failed = true
      elsif !positions.empty?
        status = 'corrected'
        result.lines << prefix + ' corrected ' + positions.join(' ')
      else
        status = 'ok'
        result.lines << prefix + ' ok'
      end
      result.blocks << [status, positions.length]
      corrected_blocks << corrected
    end
    return result if failed
    data = corrected_blocks.zip(layout.lengths).flat_map { |words, length| words.first(length) }
    parse_data(result, Bitstream.from_codewords(data), version)
    result
  end

  def decode(symbol)
    rotations = finder_rotation(symbol)
    oriented = symbol
    rotations.times { oriented = rotate(oriented) }
    adopted, mirrored = attempt(oriented), false
    if adopted.text.nil?
      second = attempt(oriented.transpose)
      unless second.text.nil?
        adopted, mirrored = second, true
      end
    end
    adopted.lines.unshift("orientation rotations #{rotations} mirrored #{mirrored ? 'yes' : 'no'}")
    adopted
  end
end

def damaged_symbol(encoding, operations)
  symbol = encoding.symbol.map(&:dup)
  operations.each do |operation, *arguments|
    case operation
    when 'flip'
      x, y = arguments
      symbol[y][x] ^= 1
    when 'fill'
      left, top, width, height, color = arguments
      (top...top + height).each { |y| (left...left + width).each { |x| symbol[y][x] = color } }
    end
  end
  counts = Hash.new(0)
  damaged_words = Array.new(encoding.block_layout.count) { Set.new }
  symbol.each_with_index do |row, y|
    row.each_with_index do |value, x|
      next if value == encoding.symbol[y][x]
      area = encoding.layout.areas[y][x]
      case area
      when QRMatrix::FUNCTION then counts['function'] += 1
      when QRMatrix::FORMAT then counts['format'] += 1
      when QRMatrix::VERSION then counts['version'] += 1
      else
        index = encoding.layout.indices[[x, y]]
        if index < 8 * encoding.block_layout.total
          counts['data'] += 1
          block, position = encoding.block_layout.placement[index / 8]
          damaged_words[block] << position
        else
          counts['remainder'] += 1
        end
      end
    end
  end
  operations.each do |operation, *_|
    symbol = rotate(symbol) if operation == 'rotate'
    symbol = symbol.transpose if operation == 'mirror'
  end
  details = %w[function format version data remainder].map { |area| "#{area} #{counts[area]}" }.join(' ')
  lines = ["check damaged operations #{operations.length}", "damage changed #{counts.values.sum} #{details}"]
  lines << "errors #{damaged_words.map(&:size).join(' ')} limit #{encoding.block_layout.degree / 2}"
  [symbol, lines]
end

def tolerance(encoding, codec, color)
  size = encoding.layout.size
  (1..size).each do |side|
    symbol = encoding.symbol.map(&:dup)
    start = (size - side) / 2
    (start...start + side).each { |y| (start...start + side).each { |x| symbol[y][x] = color } }
    return side - 1 unless codec.decode(symbol).text == encoding.request.text
  end
  size
end

class Summary
  attr_reader :scans

  def initialize
    @totals, @errors, @modes, @levels, @versions, @masks, @checks, @blocks, @scans = Array.new(9) { Hash.new(0) }
  end

  def record_error(error) = @errors[error.split.first] += 1

  def record_encoding(encoding)
    request = encoding.request
    @totals['encoded'] += 1
    @modes[request.mode] += 1
    @levels[request.level] += 1
    @totals['boosted'] += 1 if request.boosted
    @versions[request.version] += 1
    @masks[encoding.mask] += 1
    @totals['segments'] += request.segments.length
    @totals['data'] += encoding.block_layout.data
    @totals['ec'] += encoding.block_layout.degree * encoding.block_layout.count
    @totals['modules'] += encoding.layout.size**2
    @totals['dark'] += encoding.dark
  end

  def record_check(attempt, text)
    result = attempt.text.nil? ? 'failed' : (attempt.text == text ? 'ok' : 'mismatch')
    @checks[result] += 1
    attempt.blocks.each do |status, positions|
      @blocks[status] += 1
      @totals['corrected_positions'] += positions
    end
    result
  end

  def lines(request_count)
    lines = ["requests #{request_count} encoded #{@totals['encoded']} errors #{@errors.values.sum}"]
    lines << 'error_kinds ' + ERROR_KINDS.map { |kind| "#{kind} #{@errors[kind]}" }.join(' ')
    lines << 'modes ' + (MODES + ['MIXED']).map { |mode| "#{mode} #{@modes[mode]}" }.join(' ')
    lines << 'levels ' + LEVELS.map { |level| "#{level} #{@levels[level]}" }.join(' ') + " boosted #{@totals['boosted']}"
    lines << 'versions ' + (1..10).map { |v| @versions[v] }.join(' ')
    lines << 'masks ' + (0..7).map { |mask| @masks[mask] }.join(' ')
    lines << "segments #{@totals['segments']} data_codewords #{@totals['data']} ec_codewords #{@totals['ec']}"
    lines << "modules #{@totals['modules']} dark #{@totals['dark']}"
    lines << "checks #{@checks.values.sum} " + %w[ok mismatch failed].map { |status| "#{status} #{@checks[status]}" }.join(' ')
    lines << 'blocks ' + %w[ok corrected failed].map { |status| "#{status} #{@blocks[status]}" }.join(' ') + " codewords #{@totals['corrected_positions']}"
    lines << "scans #{@scans.values.sum} decoded #{@scans['decoded']} failed #{@scans['failed']}"
  end
end

def check_lines(encoding, codec, params, operations, summary)
  request = encoding.request
  path = "output/qr_#{request.id}.pbm"
  File.write(path, Render.pbm_text(encoding.symbol, params['quiet_zone'], params['scale']))
  symbol, image_line = read_image(path)
  lines = ["request #{request.id}", image_line, 'check clean']
  attempt = codec.decode(symbol)
  lines.concat(attempt.lines)
  lines << 'result ' + summary.record_check(attempt, request.text)
  unless operations.empty?
    symbol, damage_lines = damaged_symbol(encoding, operations)
    lines.concat(damage_lines)
    attempt = codec.decode(symbol)
    lines.concat(attempt.lines)
    lines << 'result ' + summary.record_check(attempt, request.text)
  end
  light, dark = tolerance(encoding, codec, 0), tolerance(encoding, codec, 1)
  lines << "tolerance light #{light} dark #{dark}"
end

def capacity_lines(codec)
  lines = []
  (1..10).each do |version|
    geometry = codec.geometry(version)
    total = codec.tables[[version, 'L']].total
    alignment = codec.alignments[version].empty? ? 'none' : codec.alignments[version].join(' ')
    lines << "version #{version} size #{geometry.size} data_modules #{geometry.data_modules} codewords #{total} remainder #{geometry.data_modules - 8 * total} alignment #{alignment}"
    LEVELS.each do |level|
      layout = codec.tables[[version, level]]
      maxima = MODES.map do |mode|
        count = 0
        count += 1 while 4 + count_width(mode, version) + data_width(mode, count + 1) <= layout.capacity
        count
      end
      lines << "level #{level} blocks #{layout.count} data #{layout.data} ec_per_block #{layout.degree} numeric #{maxima[0]} alphanumeric #{maxima[1]} byte #{maxima[2]}"
    end
  end
  lines
end

def main
  requests, params, tables, alignments, damage, scans = read_inputs
  codec, summary = Codec.new(tables, alignments), Summary.new
  Dir.mkdir('output') unless Dir.exist?('output')
  reports = %w[codes codewords bitstream selfcheck scans].to_h { |name| [name, []] }
  requests.each do |request|
    reports['codes'] << "request #{request.id}"
    error = request.prepare(codec)
    if error
      reports['codes'] << 'error ' + error
      summary.record_error(error)
      next
    end
    encoding = Encoding.new(request, codec)
    reports['codes'].concat(codes_lines(encoding, codec))
    reports['codewords'].concat(codeword_lines(encoding))
    reports['bitstream'].concat(bitstream_lines(encoding))
    summary.record_encoding(encoding)
    reports['selfcheck'].concat(check_lines(encoding, codec, params, damage[request.id], summary))
  end
  scans.each do |name, symbol|
    reports['scans'] << "scan #{name} size #{symbol.length}"
    attempt = codec.decode(symbol)
    reports['scans'].concat(attempt.lines)
    result = attempt.text.nil? ? 'failed' : 'decoded'
    reports['scans'] << 'result ' + result
    summary.scans[result] += 1
  end
  reports['capacity'], reports['summary'] = capacity_lines(codec), summary.lines(requests.length)
  reports.each { |name, lines| File.write("output/#{name}.txt", lines.map { |line| line + "\n" }.join) }
end

main if $PROGRAM_NAME == __FILE__
