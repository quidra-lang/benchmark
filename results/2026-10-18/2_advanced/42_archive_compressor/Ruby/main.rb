require_relative 'bitio'
require_relative 'lzw'
require_relative 'lz77'
require_relative 'huffman'
require_relative 'arith_coder'

module ArchiveCompressor
  METHODS = %w[STORE LZW LZ77 LZH ARITH].freeze
  STATUSES = %w[ok repaired checksum error unsupported truncated bad_header].freeze
  MODULUS = 65521

  Parameters = Struct.new(:offset_bits, :length_bits, :max_code_length, keyword_init: true)
  LzStatistics = Struct.new(:tokens, :literals, :matches, :matched, :longest, :farthest,
                            keyword_init: true)
  LzhStatistics = Struct.new(:mode, :fixed_bits, :table_bits, :code_bits, :halvings,
                             :litlen_used, :litlen_max, :offset_used, :offset_max, :slots,
                             keyword_init: true)
  EncodedFile = Struct.new(:name, :data, :payloads, :best, :lzw_stats, :lz77_stats,
                           :lzh_stats, :arith_stats, keyword_init: true) do
    def payload = payloads[best]
  end
  Entry = Struct.new(:number, :offset, :status, :valid_header, :name, :method, :original,
                     :compressed, :checksum, :start, :ending, :data, :error, :repair,
                     :computed, keyword_init: true)
  ParsedArchive = Struct.new(:size, :offset_bits, :length_bits, :declared, :entries,
                             :error, :stopped, :trailing, keyword_init: true) do
    def intact = entries.select { |entry| entry.status == 'ok' || entry.status == 'repaired' }
  end

  class HuffmanReader
    def initialize(lengths)
      codes = Huffman.canonical_codes(lengths)
      @symbols = {}
      lengths.each_with_index do |length, symbol|
        @symbols[[length, codes[symbol]]] = symbol if length.positive?
      end
      @maximum = lengths.max
    end

    def read(reader, output_position)
      raise DecodeError.new('bad_code', output_position) if @symbols.empty?

      code = 0
      1.upto(@maximum) do |width|
        code = code * 2 + reader.read(1, output_position)
        symbol = @symbols[[width, code]]
        return symbol unless symbol.nil?
      end
      raise DecodeError.new('bad_code', output_position)
    end
  end

  module_function

  def read_inputs
    lines = File.readlines('input/manifest.txt', chomp: true)
    values = lines.first(3).map { |line| line.split[1].to_i }
    parameters = Parameters.new(offset_bits: values[0], length_bits: values[1], max_code_length: values[2])
    files = lines.drop(3).map do |line|
      name = line.split[1]
      [name, File.binread(File.join('input', 'files', name))]
    end
    hexadecimal = File.readlines('input/archive.hex', chomp: true).join
    [parameters, files, [hexadecimal].pack('H*')]
  end

  def ratio(compressed, original)
    original.positive? ? (1000 * compressed / original).to_s : '-'
  end

  def method_name(number) = METHODS[number] || "##{number}"
  def hex8(value) = format('%08x', value)

  def adler32(data)
    first = 1
    second = 0
    data.each_byte do |value|
      first = (first + value) % MODULUS
      second = (second + first) % MODULUS
    end
    second * 65536 + first
  end

  def repair_one_byte(data, stored, computed)
    delta_a = (stored % 65536 - computed % 65536) % MODULUS
    delta_b = (stored / 65536 - computed / 65536) % MODULUS
    delta = if delta_a.between?(1, 255)
              delta_a
            elsif delta_a.between?(MODULUS - 255, MODULUS - 1)
              delta_a - MODULUS
            else
              return
            end
    inverse = (delta % MODULUS).pow(MODULUS - 2, MODULUS)
    distance_from_end = delta_b * inverse % MODULUS
    return unless distance_from_end.between?(1, data.bytesize)

    position = data.bytesize - distance_from_end
    before = data.getbyte(position)
    after = before + delta
    return unless after.between?(0, 255)

    repaired = data.dup
    repaired.setbyte(position, after)
    [repaired, [position, before, after]] if adler32(repaired) == stored
  end

  def decode_store(payload, original_size)
    raise DecodeError.new('end_of_data', payload.bytesize) if payload.bytesize < original_size

    payload.byteslice(0, original_size)
  end

  def encode_lz77(tokens, offset_bits, length_bits)
    writer = BitWriter.new
    tokens.each do |token|
      if token.is_a?(Integer)
        writer.write(0, 1)
        writer.write(token, 8)
      else
        distance, length = token
        writer.write(1, 1)
        writer.write(distance - 1, offset_bits)
        writer.write(length - 3, length_bits)
      end
    end
    writer.finish
  end

  def decode_lz77(payload, original_size, offset_bits, length_bits)
    reader = BitReader.new(payload)
    output = ''.b
    while output.bytesize < original_size
      if reader.read(1, output.bytesize).zero?
        output << reader.read(8, output.bytesize)
      else
        distance = reader.read(offset_bits, output.bytesize) + 1
        length = reader.read(length_bits, output.bytesize) + 3
        LZ77.copy_match(output, distance, length, original_size)
      end
    end
    output
  end

  def fixed_lengths(symbol_count)
    width = (symbol_count - 1).bit_length
    shorter = (1 << width) - symbol_count
    Array.new(symbol_count) { |symbol| symbol < shorter ? width - 1 : width }
  end

  def write_code_table(writer, lengths)
    symbol = 0
    while symbol < lengths.length
      if lengths[symbol].positive?
        writer.write(lengths[symbol], 4)
        symbol += 1
      else
        run = 1
        while run < 256 && symbol + run < lengths.length && lengths[symbol + run].zero?
          run += 1
        end
        writer.write(0, 4)
        writer.write(run - 1, 8)
        symbol += run
      end
    end
  end

  def check_code_table(lengths, output_position)
    positive = lengths.select(&:positive?)
    valid = if positive.length == 1
              positive[0] == 1
            elsif positive.length >= 2
              positive.sum { |length| 1 << (15 - length) } == 1 << 15
            else
              true
            end
    raise DecodeError.new('bad_table', output_position) unless valid
  end

  def read_code_table(reader, symbol_count, output_position)
    lengths = []
    while lengths.length < symbol_count
      length = reader.read(4, output_position)
      if length.positive?
        lengths << length
      else
        run = reader.read(8, output_position) + 1
        raise DecodeError.new('bad_table', output_position) if lengths.length + run > symbol_count

        lengths.concat(Array.new(run, 0))
      end
    end
    check_code_table(lengths, output_position)
    lengths
  end

  def token_frequencies(tokens, offset_bits, length_bits)
    literal_lengths = Array.new(256 + (1 << length_bits), 0)
    distances = Array.new(offset_bits + 1, 0)
    tokens.each do |token|
      if token.is_a?(Integer)
        literal_lengths[token] += 1
      else
        distance, length = token
        literal_lengths[256 + length - 3] += 1
        distances[(distance - 1).bit_length] += 1
      end
    end
    [literal_lengths, distances]
  end

  def write_lzh_tokens(writer, tokens, literal_lengths, distance_lengths)
    literal_codes = Huffman.canonical_codes(literal_lengths)
    distance_codes = Huffman.canonical_codes(distance_lengths)
    tokens.each do |token|
      if token.is_a?(Integer)
        writer.write(literal_codes[token], literal_lengths[token])
      else
        distance, length = token
        symbol = 256 + length - 3
        writer.write(literal_codes[symbol], literal_lengths[symbol])
        offset = distance - 1
        slot = offset.bit_length
        writer.write(distance_codes[slot], distance_lengths[slot])
        writer.write(offset - (1 << (slot - 1)), slot - 1) if slot >= 2
      end
    end
  end

  def encode_lzh(tokens, parameters)
    literal_frequencies, distance_frequencies = token_frequencies(tokens, parameters.offset_bits,
                                                                 parameters.length_bits)
    literal_lengths, literal_halvings = Huffman.limited_lengths(literal_frequencies, parameters.max_code_length)
    distance_lengths, distance_halvings = Huffman.limited_lengths(distance_frequencies, parameters.max_code_length)
    fixed = BitWriter.new
    fixed.write(0, 1)
    write_lzh_tokens(fixed, tokens, fixed_lengths(literal_lengths.length), fixed_lengths(distance_lengths.length))
    fixed_bits = fixed.bit_count - 1
    dynamic = BitWriter.new
    dynamic.write(1, 1)
    write_code_table(dynamic, literal_lengths)
    write_code_table(dynamic, distance_lengths)
    table_bits = dynamic.bit_count - 1
    write_lzh_tokens(dynamic, tokens, literal_lengths, distance_lengths)
    code_bits = dynamic.bit_count - 1 - table_bits
    use_fixed = fixed_bits <= table_bits + code_bits
    stats = LzhStatistics.new(mode: use_fixed ? 'fixed' : 'dynamic', fixed_bits: fixed_bits,
                              table_bits: table_bits, code_bits: code_bits,
                              halvings: literal_halvings + distance_halvings,
                              litlen_used: literal_lengths.count(&:positive?), litlen_max: literal_lengths.max,
                              offset_used: distance_lengths.count(&:positive?), offset_max: distance_lengths.max,
                              slots: distance_frequencies)
    [(use_fixed ? fixed : dynamic).finish, stats]
  end

  def decode_lzh(payload, original_size, offset_bits, length_bits)
    reader = BitReader.new(payload)
    literal_count = 256 + (1 << length_bits)
    distance_count = offset_bits + 1
    if reader.read(1) == 1
      literal_lengths = read_code_table(reader, literal_count, 0)
      distance_lengths = read_code_table(reader, distance_count, 0)
    else
      literal_lengths = fixed_lengths(literal_count)
      distance_lengths = fixed_lengths(distance_count)
    end
    literal_table = HuffmanReader.new(literal_lengths)
    distance_table = HuffmanReader.new(distance_lengths)
    output = ''.b
    while output.bytesize < original_size
      symbol = literal_table.read(reader, output.bytesize)
      if symbol < 256
        output << symbol
      else
        length = symbol - 253
        slot = distance_table.read(reader, output.bytesize)
        offset = slot >= 2 ? (1 << (slot - 1)) + reader.read(slot - 1, output.bytesize) : slot
        LZ77.copy_match(output, offset + 1, length, original_size)
      end
    end
    output
  end

  def decode_payload(method, payload, original_size, offset_bits, length_bits)
    case method
    when 0 then decode_store(payload, original_size)
    when 1 then LZW.decode(payload, original_size)
    when 2 then decode_lz77(payload, original_size, offset_bits, length_bits)
    when 3 then decode_lzh(payload, original_size, offset_bits, length_bits)
    when 4 then ArithCoder.decode(payload, original_size)
    end
  end

  def encode_file(name, data, parameters)
    tokens = LZ77.tokenize(data, parameters.offset_bits, parameters.length_bits)
    lzw_payload, lzw_stats = LZW.encode(data)
    lz77_payload = encode_lz77(tokens, parameters.offset_bits, parameters.length_bits)
    lzh_payload, lzh_stats = encode_lzh(tokens, parameters)
    arith_payload, arith_stats = ArithCoder.encode(data)
    payloads = [data, lzw_payload, lz77_payload, lzh_payload, arith_payload]
    best = payloads.each_index.min_by { |method| [payloads[method].bytesize, method] }
    matches = tokens.reject { |token| token.is_a?(Integer) }
    lz77_stats = LzStatistics.new(tokens: tokens.length, literals: tokens.length - matches.length,
                                 matches: matches.length, matched: matches.sum { |_distance, length| length },
                                 longest: matches.map(&:last).max || 0, farthest: matches.map(&:first).max || 0)
    EncodedFile.new(name: name, data: data, payloads: payloads, best: best, lzw_stats: lzw_stats,
                    lz77_stats: lz77_stats, lzh_stats: lzh_stats, arith_stats: arith_stats)
  end

  def build_archive(encodings, parameters)
    archive = 'TXAR'.b + [parameters.offset_bits, parameters.length_bits, encodings.length].pack('CCn')
    encodings.each do |encoding|
      header = [encoding.name.bytesize].pack('C') + encoding.name.b
      header << [encoding.best, encoding.data.bytesize, encoding.payload.bytesize,
                 adler32(encoding.data)].pack('CNNN')
      header << (header.bytes.sum % 256)
      archive << header << encoding.payload
    end
    archive
  end

  def read_entry_header(archive, number, position)
    name_length = archive.getbyte(position)
    name = archive.byteslice(position + 1, name_length)
    cursor = position + 1 + name_length
    start = position + 15 + name_length
    original, compressed, checksum = archive.byteslice(cursor + 1, 12).unpack('N3')
    valid_name = name_length.between?(1, 32) && name.match?(/\A[a-z0-9._-]+\z/n)
    valid_check = archive.byteslice(position, start - position - 1).bytes.sum % 256 == archive.getbyte(start - 1)
    Entry.new(number: number, offset: position, valid_header: valid_name && valid_check,
              name: valid_name && valid_check ? name : '', method: archive.getbyte(cursor),
              original: original, compressed: compressed, checksum: checksum,
              start: start, ending: start + compressed)
  end

  def examine_payload(entry, archive, offset_bits, length_bits)
    begin
      entry.data = decode_payload(entry.method, archive.byteslice(entry.start, entry.compressed),
                                  entry.original, offset_bits, length_bits)
    rescue DecodeError => error
      entry.status = 'error'
      entry.error = error
      return
    end
    entry.computed = adler32(entry.data)
    if entry.computed == entry.checksum
      entry.status = 'ok'
      return
    end
    repair = repair_one_byte(entry.data, entry.checksum, entry.computed)
    if repair
      entry.data, entry.repair = repair
      entry.status = 'repaired'
    else
      entry.status = 'checksum'
    end
  end

  def parse_archive(archive)
    result = ParsedArchive.new(size: archive.bytesize, entries: [], stopped: false, trailing: 0)
    if archive.bytesize < 8 || archive.byteslice(0, 4) != 'TXAR'
      result.error = 'bad_magic'
      return result
    end
    result.offset_bits = archive.getbyte(4)
    result.length_bits = archive.getbyte(5)
    unless result.offset_bits.between?(6, 12) && result.length_bits.between?(2, 5)
      result.error = 'bad_params'
      return result
    end
    result.declared = archive.byteslice(6, 2).unpack1('n')
    position = 8
    1.upto(result.declared) do |number|
      if position >= archive.bytesize || position + 15 + archive.getbyte(position) > archive.bytesize
        result.entries << Entry.new(number: number, offset: position, status: 'truncated', valid_header: false)
        result.stopped = true
        break
      end
      entry = read_entry_header(archive, number, position)
      result.entries << entry
      unless entry.valid_header
        entry.status = 'bad_header'
        position = entry.ending
        if position > archive.bytesize
          result.stopped = true
          break
        end
        next
      end
      if entry.ending > archive.bytesize
        entry.status = 'truncated'
        result.stopped = true
        break
      end
      if entry.method >= METHODS.length
        entry.status = 'unsupported'
      else
        examine_payload(entry, archive, result.offset_bits, result.length_bits)
      end
      position = entry.ending
    end
    result.trailing = archive.bytesize - position unless result.stopped
    result
  end

  def verify_archive(archive, originals)
    parsed = parse_archive(archive)
    verified = parsed.entries.each_with_index.count do |entry, index|
      entry.status == 'ok' && entry.data == originals[index]
    end
    [parsed.entries.length, verified]
  end

  def sizes_report(encodings, parameters, archive, examined, verified)
    lines = ["params offset_bits #{parameters.offset_bits} length_bits #{parameters.length_bits} " \
             "window #{1 << parameters.offset_bits} lookahead #{(1 << parameters.length_bits) + 2} " \
             "max_code_length #{parameters.max_code_length}"]
    totals = Array.new(METHODS.length, 0)
    chosen = Array.new(METHODS.length, 0)
    original_total = best_total = 0
    encodings.each do |encoding|
      original = encoding.data.bytesize
      original_total += original
      chosen[encoding.best] += 1
      best_total += encoding.payload.bytesize
      fields = ["file #{encoding.name} original #{original}"]
      METHODS.each_with_index do |name, method|
        compressed = encoding.payloads[method].bytesize
        totals[method] += compressed
        fields << "#{name} #{compressed} #{ratio(compressed, original)}"
      end
      fields << "best #{METHODS[encoding.best]}"
      lines << fields.join(' ')
    end
    fields = ["total original #{original_total}"]
    METHODS.zip(totals).each do |name, total|
      fields << "#{name} #{total} #{ratio(total, original_total)}"
    end
    fields << "best #{best_total} #{ratio(best_total, original_total)}"
    lines << fields.join(' ')
    lines << 'chosen ' + METHODS.zip(chosen).map { |name, count| "#{name} #{count}" }.join(' ')
    lines << "archive bytes #{archive.bytesize} entries #{encodings.length} ratio #{ratio(archive.bytesize, original_total)}"
    lines << "verify entries #{examined} ok #{verified}"
  end

  def analysis_report(encodings)
    encodings.flat_map do |encoding|
      name = encoding.name
      zw = encoding.lzw_stats
      z = encoding.lz77_stats
      zh = encoding.lzh_stats
      arithmetic = encoding.arith_stats
      ["lzw #{name} codes #{zw.codes} clears #{zw.clears} widths #{zw.widths.join(' ')} longest #{zw.longest}",
       "lz77 #{name} tokens #{z.tokens} literals #{z.literals} matches #{z.matches} matched #{z.matched} " \
       "longest #{z.longest} farthest #{z.farthest}",
       "lzh #{name} mode #{zh.mode} fixed_bits #{zh.fixed_bits} table_bits #{zh.table_bits} " \
       "code_bits #{zh.code_bits} halvings #{zh.halvings} litlen_used #{zh.litlen_used} " \
       "litlen_max #{zh.litlen_max} offset_used #{zh.offset_used} offset_max #{zh.offset_max}",
       "slots #{name} #{zh.slots.join(' ')}",
       "arith #{name} bits #{arithmetic.bits} contexts #{arithmetic.contexts} rescales #{arithmetic.rescales}"]
    end
  end

  def listing_report(parsed)
    return ["archive bytes #{parsed.size} error #{parsed.error}"] if parsed.error

    lines = ["archive bytes #{parsed.size} offset_bits #{parsed.offset_bits} " \
             "length_bits #{parsed.length_bits} entries #{parsed.declared}"]
    totals = Array.new(METHODS.length) { [0, 0, 0] }
    listed = 0
    parsed.entries.each do |entry|
      prefix = "entry #{entry.number} offset #{entry.offset}"
      unless entry.valid_header
        lines << "#{prefix} #{entry.status == 'bad_header' ? 'bad_header' : 'truncated header'}"
        next
      end
      listed += 1
      lines << "#{prefix} method #{method_name(entry.method)} original #{entry.original} " \
               "compressed #{entry.compressed} ratio #{ratio(entry.compressed, entry.original)} " \
               "adler #{hex8(entry.checksum)} name #{entry.name}"
      next unless entry.method < METHODS.length

      values = totals[entry.method]
      values[0] += 1
      values[1] += entry.original
      values[2] += entry.compressed
    end
    METHODS.zip(totals).each do |method, (count, original, compressed)|
      lines << "method #{method} entries #{count} original #{original} compressed #{compressed} " \
               "ratio #{ratio(compressed, original)}"
    end
    lines << "end listed #{listed} of #{parsed.declared} stop #{parsed.stopped ? 'truncated' : 'complete'} " \
             "trailing #{parsed.trailing}"
  end

  def entry_test_line(entry, archive_size)
    prefix = "entry #{entry.number} offset #{entry.offset}"
    unless entry.valid_header
      return "#{prefix} status #{entry.status == 'bad_header' ? 'bad_header' : 'truncated header'}"
    end

    line = "#{prefix} name #{entry.name} method #{method_name(entry.method)} status #{entry.status}"
    case entry.status
    when 'repaired'
      position, before, after = entry.repair
      line += " byte #{position} from #{before} to #{after}"
    when 'checksum'
      line += " stored #{hex8(entry.checksum)} computed #{hex8(entry.computed)}"
    when 'error'
      line += " #{entry.error.kind} at #{entry.error.position}"
    when 'truncated'
      line += " payload have #{archive_size - entry.start} need #{entry.compressed}"
    end
    line
  end

  def test_report(parsed, salvaged, salvage_archive, verified)
    if parsed.error
      lines = ["archive error #{parsed.error}"]
    else
      lines = parsed.entries.map { |entry| entry_test_line(entry, parsed.size) }
      counts = parsed.entries.each_with_object(Hash.new(0)) { |entry, hash| hash[entry.status] += 1 }
      summary = "summary entries #{parsed.declared} checked #{parsed.entries.length}"
      summary += ' ' + STATUSES.map { |status| "#{status} #{counts[status]}" }.join(' ')
      summary += " missing #{parsed.declared - parsed.entries.length} trailing #{parsed.trailing}"
      lines << summary
    end
    parsed.intact.zip(salvaged).each do |entry, encoding|
      lines << "salvage #{entry.name} method #{METHODS[encoding.best]} compressed #{encoding.payload.bytesize} " \
               "was #{method_name(entry.method)} #{entry.compressed}"
    end
    original_total = salvaged.sum { |encoding| encoding.data.bytesize }
    lines << "salvaged entries #{salvaged.length} bytes #{salvage_archive.bytesize} " \
             "original #{original_total} verified #{verified}"
  end

  def text_lines(data)
    data.empty? ? [] : data.split("\n", -1)[0...-1]
  end

  def extraction_report(entries)
    entries.flat_map do |entry|
      contents = text_lines(entry.data)
      words = contents.sum { |line| line.scan(/[^ ]+/).length }
      longest = contents.map(&:bytesize).max || 0
      ["file #{entry.name} bytes #{entry.data.bytesize} lines #{contents.length} words #{words} longest #{longest}",
       *contents]
    end
  end

  def edit_list(old, new)
    old_count = old.length
    new_count = new.length
    below = Array.new(new_count + 1, 0)
    current = Array.new(new_count + 1, 0)
    decisions = Array.new(old_count)
    # Retain one deletion-choice bit per cell, rather than the full LCS matrix.
    (old_count - 1).downto(0) do |i|
      deletions = "\0".b * ((new_count + 7) / 8)
      right = 0
      (new_count - 1).downto(0) do |j|
        if old[i] == new[j]
          length = below[j + 1] + 1
        elsif below[j] >= right
          length = below[j]
          byte = j / 8
          deletions.setbyte(byte, deletions.getbyte(byte) | (1 << (j % 8)))
        else
          length = right
        end
        current[j] = length
        right = length
      end
      decisions[i] = deletions
      below, current = current, below
    end
    edits = []
    i = j = 0
    while i < old_count || j < new_count
      if i < old_count && j < new_count && old[i] == new[j]
        i += 1
        j += 1
      elsif j == new_count || (i < old_count && (decisions[i].getbyte(j / 8) & (1 << (j % 8))) != 0)
        edits << ['-', i + 1, old[i]]
        i += 1
      else
        edits << ['+', j + 1, new[j]]
        j += 1
      end
    end
    edits
  end

  def comparison_report(entries, files)
    manifest = files.to_h
    seen = {}
    lines = []
    entries.each do |entry|
      name = entry.name
      seen[name] = true
      unless manifest.key?(name)
        lines << "archive_only #{name}"
        next
      end
      old = text_lines(entry.data)
      new = text_lines(manifest[name])
      if old == new
        lines << "same #{name} lines #{old.length}"
        next
      end
      first = 0
      first += 1 while first < [old.length, new.length].min && old[first] == new[first]
      edits = edit_list(old, new)
      removed = edits.count { |sign, _number, _content| sign == '-' }
      lines << "differs #{name} first_line #{first + 1} archive_lines #{old.length} " \
               "manifest_lines #{new.length} removed #{removed} added #{edits.length - removed}"
      edits.each { |sign, number, content| lines << "#{sign}#{number}:#{content}" }
    end
    files.each { |name, _data| lines << "new #{name}" unless seen.key?(name) }
    lines
  end

  def salvage_archive(parsed, parameters)
    salvage_parameters = if parsed.error
                           parameters
                         else
                           Parameters.new(offset_bits: parsed.offset_bits, length_bits: parsed.length_bits,
                                          max_code_length: parameters.max_code_length)
                         end
    encodings = parsed.intact.map { |entry| encode_file(entry.name, entry.data, salvage_parameters) }
    archive = build_archive(encodings, salvage_parameters)
    _examined, verified = verify_archive(archive, encodings.map(&:data))
    [archive, encodings, verified]
  end

  def write_lines(name, lines)
    File.open(File.join('output', name), 'wb') do |file|
      lines.each do |line|
        file.write(line)
        file.write("\n")
      end
    end
  end

  def write_hex(name, archive)
    write_lines(name, archive.bytes.each_slice(32).map { |group| group.pack('C*').unpack1('H*') })
  end

  def main
    parameters, files, supplied_archive = read_inputs
    encodings = files.map { |name, data| encode_file(name, data, parameters) }
    created = build_archive(encodings, parameters)
    examined, verified = verify_archive(created, files.map(&:last))
    parsed = parse_archive(supplied_archive)
    salvaged, salvage_encodings, salvage_verified = salvage_archive(parsed, parameters)
    Dir.mkdir('output') unless Dir.exist?('output')
    write_lines('sizes.txt', sizes_report(encodings, parameters, created, examined, verified))
    write_lines('analysis.txt', analysis_report(encodings))
    write_hex('archive.hex', created)
    write_lines('listing.txt', listing_report(parsed))
    write_lines('test_report.txt', test_report(parsed, salvage_encodings, salvaged, salvage_verified))
    write_lines('extracted.txt', extraction_report(parsed.intact))
    write_lines('compare.txt', comparison_report(parsed.intact, files))
    write_hex('salvaged.hex', salvaged)
  end
end

ArchiveCompressor.main if $PROGRAM_NAME == __FILE__
