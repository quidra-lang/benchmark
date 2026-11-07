require 'fileutils'
require 'ostruct'
require_relative 'image_io'
require_relative 'color'
require_relative 'dct'
require_relative 'entropy'
require_relative 'bitstream'

module JPEG
  Component = Struct.new(:identifier, :h, :v, :tq, :td, :ta)
  Block = Struct.new(:mcu, :component, :bx, :by)
  Symbol = Struct.new(:table, :value, :extra, :width)
  COMPONENT_NAMES = %w[Y Cb Cr].freeze
  TABLE_KEYS = Entropy::TABLE_KEYS

  def self.standard_components(h, v)
    [Component.new(1, h, v, 0, 0, 0), Component.new(2, 1, 1, 1, 1, 1), Component.new(3, 1, 1, 1, 1, 1)]
  end

  class Layout
    attr_reader :width, :height, :components, :restart_interval, :factors, :hmax, :vmax,
                :mx, :my, :mcus, :blocks_per_mcu, :blocks, :intervals

    def initialize(width, height, components, restart_interval)
      @width, @height, @components, @restart_interval = width, height, components, restart_interval
      @factors = components.map { |c| [c.h, c.v] }
      @hmax, @vmax = components.map(&:h).max, components.map(&:v).max
      @mx = (width + 8 * @hmax - 1) / (8 * @hmax)
      @my = (height + 8 * @vmax - 1) / (8 * @vmax)
      @mcus = @mx * @my
      @blocks_per_mcu = components.sum { |c| c.h * c.v }
      @blocks = []
      @mcus.times do |mcu|
        components.each_with_index do |c, index|
          c.v.times do |v|
            c.h.times { |h| @blocks << Block.new(mcu, index, c.h * (mcu % @mx) + h, c.v * (mcu / @mx) + v) }
          end
        end
      end
      step = restart_interval.zero? ? @mcus : restart_interval
      @intervals = (0...@mcus).step(step).map { |first| [first, [step, @mcus - first].min] }
    end

    def interval_blocks(interval)
      first, count = @intervals[interval]
      (first * @blocks_per_mcu...(first + count) * @blocks_per_mcu)
    end
  end

  class Codec
    def initialize(transform, basic_quantization, standard_tables)
      @transform, @basic_quantization, @standard_tables = transform, basic_quantization, standard_tables
    end

    def word(value)
      [value / 256, value % 256]
    end

    def read_word(data, offset)
      256 * data[offset] + data[offset + 1]
    end

    def segment(marker, contents)
      [0xff, marker] + word(contents.length + 2) + contents
    end

    def prepare(image, quality, sampling, restart_interval)
      h, v = { '444' => [1, 1], '422' => [2, 1], '420' => [2, 2] }.fetch(sampling)
      layout = Layout.new(image.first.length, image.length, JPEG.standard_components(h, v), restart_interval)
      planes = Color.component_planes(Color.split_planes(image), layout.factors, layout.mx, layout.my)
      quantization = DCT.quantization_tables(@basic_quantization, quality)
      coefficients = layout.blocks.map do |block|
        plane = planes[block.component]
        pixels = plane[8 * block.by, 8].map { |row| row[8 * block.bx, 8] }
        transformed = DCT.forward(pixels, @transform)
        table = quantization[layout.components[block.component].tq]
        DCT.zigzag(DCT.quantize(transformed, table))
      end
      OpenStruct.new(layout: layout, planes: planes, quantization: quantization, coefficients: coefficients)
    end

    def build_symbols(prepared)
      layout = prepared.layout
      frequencies = TABLE_KEYS.to_h { |key| [key, Array.new(256, 0)] }
      blocks, differences = [], []
      layout.intervals.each_index do |interval|
        predictors = [0, 0, 0]
        layout.interval_blocks(interval).each do |number|
          block = layout.blocks[number]
          component = layout.components[block.component]
          sequence = prepared.coefficients[number]
          difference = sequence[0] - predictors[block.component]
          predictors[block.component] = sequence[0]
          differences << difference
          bits, size = Entropy.extra_bits(difference)
          symbols = [Symbol.new([0, component.td], size, bits, size)]
          ac_table = [1, component.ta]
          run = 0
          sequence.drop(1).each do |value|
            if value.zero?
              run += 1
              next
            end
            while run >= 16
              symbols << Symbol.new(ac_table, 0xf0, 0, 0)
              run -= 16
            end
            bits, size = Entropy.extra_bits(value)
            symbols << Symbol.new(ac_table, 16 * run + size, bits, size)
            run = 0
          end
          symbols << Symbol.new(ac_table, 0, 0, 0) if run.positive?
          symbols.each { |s| frequencies[s.table][s.value] += 1 }
          blocks << symbols
        end
      end
      [blocks, differences, frequencies]
    end

    def header(layout, quantization, tables)
      header = [0xff, 0xd8]
      contents = []
      2.times { |id| contents.concat([id] + DCT.zigzag(quantization[id])) }
      header.concat(segment(0xdb, contents))
      contents = [8] + word(layout.height) + word(layout.width) + [3]
      layout.components.each { |c| contents.concat([c.identifier, 16 * c.h + c.v, c.tq]) }
      header.concat(segment(0xc0, contents))
      contents = []
      TABLE_KEYS.each do |key|
        table = tables[key]
        contents.concat([16 * key[0] + key[1]] + table.counts + table.symbols)
      end
      header.concat(segment(0xc4, contents))
      header.concat(segment(0xdd, word(layout.restart_interval))) if layout.restart_interval.positive?
      contents = [3]
      layout.components.each { |c| contents.concat([c.identifier, 16 * c.td + c.ta]) }
      header.concat(segment(0xda, contents + [0, 63, 0]))
      header
    end

    def encode_prepared(prepared, mode)
      symbols, differences, frequencies = build_symbols(prepared)
      tables = mode == 'standard' ? @standard_tables : TABLE_KEYS.to_h { |key| [key, Entropy.optimized_table(frequencies[key])] }
      header = header(prepared.layout, prepared.quantization, tables)
      writer = Bitstream::BitWriter.new
      block_bits = Array.new(prepared.coefficients.length, 0)
      intervals = []
      prepared.layout.intervals.each_with_index do |(first, count), interval|
        writer.restart(interval - 1) if interval.positive?
        start = writer.data.length
        prepared.layout.interval_blocks(interval).each do |number|
          symbols[number].each do |symbol|
            length, code = tables[symbol.table].codes[symbol.value]
            writer.write(code, length)
            writer.write(symbol.extra, symbol.width)
            block_bits[number] += length + symbol.width
          end
        end
        writer.pad
        intervals << [first, count, header.length + start, writer.data.length - start]
      end
      OpenStruct.new(layout: prepared.layout, planes: prepared.planes, quantization: prepared.quantization,
                     coefficients: prepared.coefficients, tables: tables, frequencies: frequencies,
                     differences: differences, block_bits: block_bits, intervals: intervals,
                     data: header + writer.data + [0xff, 0xd9], header_bytes: header.length,
                     scan_bytes: writer.data.length, padding_bits: writer.padding_bits, stuffed_bytes: writer.stuffed_bytes)
    end

    def encode(image, quality, sampling, mode, restart_interval)
      encode_prepared(prepare(image, quality, sampling, restart_interval), mode)
    end

    def parse_header(data)
      position = 2
      segments = [[0, 'SOI', 0]]
      quantization, tables = {}, {}
      restart_interval = 0
      width = height = components = nil
      names = { 0xc0 => 'SOF0', 0xc4 => 'DHT', 0xdb => 'DQT', 0xdd => 'DRI', 0xda => 'SOS', 0xfe => 'COM' }
      loop do
        marker = data[position + 1]
        length = read_word(data, position + 2)
        contents = data[position + 4, length - 2]
        name = marker.between?(0xe0, 0xef) ? "APP#{marker - 0xe0}" : names.fetch(marker)
        segments << [position, name, length]
        position += length + 2
        case marker
        when 0xdb
          contents.each_slice(65) { |group| quantization[group[0]] = DCT.unzigzag(group.drop(1)) }
        when 0xc4
          offset = 0
          while offset < contents.length
            table_class, id = contents[offset].divmod(16)
            counts = contents[offset + 1, 16]
            size = counts.sum
            tables[[table_class, id]] = Entropy::HuffmanTable.new(counts, contents[offset + 17, size])
            offset += 17 + size
          end
        when 0xc0
          height, width = read_word(contents, 1), read_word(contents, 3)
          components = Array.new(3) do |index|
            offset = 6 + 3 * index
            h, v = contents[offset + 1].divmod(16)
            Component.new(contents[offset], h, v, contents[offset + 2], 0, 0)
          end
        when 0xdd
          restart_interval = read_word(contents, 0)
        when 0xda
          components.each_with_index do |component, index|
            component.td, component.ta = contents[2 + 2 * index].divmod(16)
          end
          break
        end
      end
      segments << [data.length - 2, 'EOI', 0]
      OpenStruct.new(layout: Layout.new(width, height, components, restart_interval), quantization: quantization,
                     tables: tables, segments: segments, scan_start: position, scan_bytes: data.length - 2 - position)
    end

    def read_symbol(reader, table)
      code = 0
      (1..16).each do |length|
        code = 2 * code + reader.bit
        key = [length, code]
        return table.decode[key] if table.decode.key?(key)
      end
      raise Bitstream::DecodeError, 'code'
    end

    def decode_block(reader, component_index, component, tables, predictors)
      coefficients = Array.new(64, 0)
      size = read_symbol(reader, tables[[0, component.td]])
      predictors[component_index] += Entropy.amplitude(reader.read(size), size)
      coefficients[0] = predictors[component_index]
      index = 1
      while index <= 63
        symbol = read_symbol(reader, tables[[1, component.ta]])
        break if symbol.zero?
        run, size = symbol.divmod(16)
        index += run
        raise Bitstream::DecodeError, 'index' if index > 63
        coefficients[index] = Entropy.amplitude(reader.read(size), size) if size.positive?
        index += 1
      end
      coefficients
    end

    def decode_intervals(data, parsed)
      layout = parsed.layout
      coefficients = Array.new(layout.blocks.length) { Array.new(64, 0) }
      states = Array.new(layout.intervals.length) { { state: 'lost' } }
      reader = Bitstream::BitReader.new(data, parsed.scan_start)
      interval = 0
      while interval < layout.intervals.length
        predictors = [0, 0, 0]
        pending = []
        current_mcu = layout.intervals[interval][0]
        begin
          layout.interval_blocks(interval).each do |number|
            block = layout.blocks[number]
            current_mcu = block.mcu
            component = layout.components[block.component]
            pending << decode_block(reader, block.component, component, parsed.tables, predictors)
          end
          reader.discard
          expected = interval < layout.intervals.length - 1 ? 0xd0 + interval % 8 : 0xd9
          raise Bitstream::DecodeError, 'sync' unless data[reader.position] == 0xff && data[reader.position + 1] == expected
          layout.interval_blocks(interval).each_with_index { |number, i| coefficients[number] = pending[i] }
          states[interval] = { state: 'ok' }
          reader.position += 2
          interval += 1
        rescue Bitstream::DecodeError => error
          offset = reader.position
          reader.discard
          resync = Bitstream.find_resync(data, offset)
          states[interval] = { state: 'damaged', kind: error.kind, mcu: current_mcu, offset: offset, resync: resync }
          marker = data[resync + 1]
          break if marker == 0xd9
          interval += 1 + ((marker - 0xd0 - interval) % 8)
          reader.position = resync + 2
        end
      end
      [coefficients, states]
    end

    def reconstruct_component(layout, component_index, coefficients, quantization, keep = 64)
      component = layout.components[component_index]
      width, height = 8 * component.h * layout.mx, 8 * component.v * layout.my
      plane = Array.new(height) { Array.new(width, 128) }
      table = quantization[component.tq]
      layout.blocks.each_with_index do |block, number|
        next unless block.component == component_index
        pixels = DCT.inverse(DCT.dequantize(coefficients[number], table, keep), @transform)
        pixels.each_with_index { |row, y| plane[8 * block.by + y][8 * block.bx, 8] = row }
      end
      plane
    end

    def decode(data)
      parsed = parse_header(data)
      coefficients, states = decode_intervals(data, parsed)
      planes = Array.new(3) { |index| reconstruct_component(parsed.layout, index, coefficients, parsed.quantization) }
      expanded = Color.upsample(planes, parsed.layout.factors, parsed.layout.width, parsed.layout.height)
      parsed.coefficients, parsed.states = coefficients, states
      parsed.planes, parsed.expanded = planes, expanded
      parsed.image = Color.combine_rgb(expanded)
      parsed
    end

    def repair(decoded)
      source = decoded.layout
      first = source.components.first
      layout = Layout.new(source.width, source.height, JPEG.standard_components(first.h, first.v), source.restart_interval)
      quantization = { 0 => decoded.quantization[first.tq], 1 => decoded.quantization[source.components[1].tq] }
      prepared = OpenStruct.new(layout: layout, planes: nil, quantization: quantization, coefficients: decoded.coefficients)
      encode_prepared(prepared, 'optimized')
    end
  end

  def self.psnr(first, second)
    error = 0
    first.each_with_index { |a, i| error += (a - second[i])**2 }
    error.zero? ? 'inf' : format('%.2f', 10 * Math.log10((65025 * first.length).to_f / error))
  end

  def self.quality_metrics(original, original_planes, decoded)
    metrics = original_planes.each_with_index.map { |plane, i| psnr(plane.flatten, decoded.expanded[i].flatten) }
    metrics << psnr(original.flatten, decoded.image.flatten)
    maximum = original.flatten.zip(decoded.image.flatten).map { |a, b| (a - b).abs }.max
    [metrics, maximum]
  end

  def self.bits_per_pixel(bytes, width, height)
    a, b = 8 * bytes, width * height
    divisor = a.gcd(b)
    "#{a / divisor}/#{b / divisor}"
  end

  def self.write_lines(path, lines)
    File.write(path, lines.join("\n") + "\n")
  end

  class Experiment
    def initialize(image, parameters, codec, stream)
      @image, @parameters, @codec, @stream = image, parameters, codec, stream
      @width, @height = image.first.length, image.length
      @original_planes = Color.split_planes(image)
      @quality = parameters['qualities'].first
      @sampling, @mode, @restart = parameters.values_at('sampling', 'huffman', 'restart_interval')
      @prepared, @encodings, @decodings = {}, {}, {}
    end

    def encoding(quality, sampling = @sampling, mode = @mode)
      @encodings[[quality, sampling, mode]] ||= begin
        prepared = @prepared[[quality, sampling]] ||= @codec.prepare(@image, quality, sampling, @restart)
        @codec.encode_prepared(prepared, mode)
      end
    end

    def decoding(quality, sampling = @sampling)
      @decodings[[quality, sampling]] ||= @codec.decode(encoding(quality, sampling).data)
    end

    def rate_distortion
      lines = ['quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error']
      @parameters['qualities'].each do |quality|
        standard = encoding(quality, @sampling, 'standard')
        optimized = encoding(quality, @sampling, 'optimized')
        selected = encoding(quality)
        metrics, maximum = JPEG.quality_metrics(@image, @original_planes, decoding(quality))
        lines << ([quality, standard.data.length, optimized.data.length,
                   JPEG.bits_per_pixel(selected.data.length, @width, @height)] + metrics + [maximum]).join(',')
      end
      lines
    end

    def block_statistics(encoded, decoded)
      lines = ["blocks #{encoded.layout.blocks.length}"]
      errors = []
      encoded.layout.blocks.each_with_index do |block, number|
        sequence = encoded.coefficients[number]
        original, restored = encoded.planes[block.component], decoded.planes[block.component]
        error = 0
        (8 * block.by...8 * block.by + 8).each do |y|
          (8 * block.bx...8 * block.bx + 8).each { |x| error += (original[y][x] - restored[y][x])**2 }
        end
        errors << error
        nonzero = sequence.drop(1).count { |value| value != 0 }
        last = sequence.each_index.select { |i| sequence[i] != 0 }.max || 0
        lines << "block #{number} #{COMPONENT_NAMES[block.component]} #{block.bx} #{block.by} dc #{sequence[0]} diff #{encoded.differences[number]} nonzero #{nonzero} last #{last} bits #{encoded.block_bits[number]} sse #{error}"
      end
      [lines, errors]
    end

    def huffman_lines(encoded)
      lines = []
      TABLE_KEYS.each_with_index do |key, i|
        table, frequencies = encoded.tables[key], encoded.frequencies[key]
        bits = table.symbols.sum { |symbol| frequencies[symbol] * table.codes[symbol][0] }
        lines << "table #{Entropy::TABLE_NAMES[i]} class #{key[0]} id #{key[1]} symbols #{table.symbols.length} coded #{frequencies.sum} bits #{bits}"
        lines << "counts #{table.counts.join(' ')}"
        table.symbols.each do |symbol|
          length, code = table.codes[symbol]
          lines << "symbol #{format('%02x', symbol)} length #{length} code #{code.to_s(2).rjust(length, '0')} count #{frequencies[symbol]}"
        end
      end
      lines
    end

    def thumbnail(decoded)
      layout = decoded.layout
      dc_values = layout.blocks.each_with_index.to_h { |b, i| [[b.component, b.bx, b.by], decoded.coefficients[i][0]] }
      Array.new((@height + 7) / 8) do |y|
        Array.new((@width + 7) / 8) do |x|
          values = layout.components.each_with_index.map do |c, i|
            bx, by = x * c.h / layout.hmax, y * c.v / layout.vmax
            dc = dc_values[[i, bx, by]]
            divisor = decoded.quantization[c.tq][0][0]
            ((dc * divisor + 4) / 8 + 128).clamp(0, 255)
          end
          Color.to_rgb(*values)
        end
      end
    end

    def reference_report(encoded, decoded, errors)
      layout = encoded.layout
      counts = layout.components.map { |c| c.h * c.v * layout.mcus }
      lines = ["image #{@width} #{@height}",
               "sampling #{@sampling} mcu #{8 * layout.hmax} #{8 * layout.vmax} grid #{layout.mx} #{layout.my}",
               "padded #{8 * layout.hmax * layout.mx} #{8 * layout.vmax * layout.my}",
               "blocks #{counts.join(' ')}", "restart_interval #{@restart} markers #{layout.intervals.length - 1}",
               "huffman #{@mode}", "quality #{@quality}"]
      2.times { |id| lines << "quant #{id} #{DCT.zigzag(encoded.quantization[id]).join(' ')}" }
      lines << 'symbols ' + TABLE_KEYS.map { |key| encoded.frequencies[key].sum }.join(' ')
      eob = encoded.frequencies[[1, 0]][0] + encoded.frequencies[[1, 1]][0]
      zrl = encoded.frequencies[[1, 0]][0xf0] + encoded.frequencies[[1, 1]][0xf0]
      lines << "eob #{eob} zrl #{zrl}"
      lines << "zero_ac_blocks #{encoded.coefficients.count { |s| s.drop(1).all?(&:zero?) }}"
      nonzero = (0...64).map { |i| encoded.coefficients.count { |s| s[i] != 0 } }
      lines << "nonzero #{nonzero.join(' ')}"
      COMPONENT_NAMES.each_with_index do |name, c|
        numbers = layout.blocks.each_index.select { |i| layout.blocks[i].component == c }
        bits = numbers.sum { |i| encoded.block_bits[i] }
        nonzero_count = numbers.sum { |i| encoded.coefficients[i].count { |v| v != 0 } }
        error = numbers.sum { |i| errors[i] }
        lines << "component #{name} bits #{bits} nonzero #{nonzero_count} sse #{error}"
      end
      lines.concat(["padding_bits #{encoded.padding_bits}", "stuffed_bytes #{encoded.stuffed_bytes}",
                    "header_bytes #{encoded.header_bytes}", "scan_bytes #{encoded.scan_bytes}", "total_bytes #{encoded.data.length}"])
      encoded.intervals.each_with_index { |values, i| lines << "interval #{i} #{values.join(' ')}" }
      histogram = Array.new(8, 0)
      @image.flatten.zip(decoded.image.flatten).each do |a, b|
        difference = (a - b).abs
        bin = [1, 2, 4, 8, 16, 32, 64].count { |bound| difference >= bound }
        histogram[bin] += 1
      end
      lines << "error_histogram #{histogram.join(' ')}"
      @parameters['truncate'].each do |keep|
        plane = @codec.reconstruct_component(decoded.layout, 0, decoded.coefficients, decoded.quantization, keep)
        cropped = plane.first(@height).flat_map { |row| row.first(@width) }
        lines << "truncate #{keep} #{JPEG.psnr(@original_planes[0].flatten, cropped)}"
      end
      lines
    end

    def sampling_comparison
      %w[444 422 420].map do |sampling|
        encoded = encoding(@quality, sampling)
        metrics, = JPEG.quality_metrics(@image, @original_planes, decoding(@quality, sampling))
        "sampling_compare #{sampling} #{encoded.data.length} #{metrics.drop(1).join(' ')}"
      end
    end

    def generations(reference, reference_decoded)
      lines = []
      previous = @image
      (1..@parameters['generations']).each do |generation|
        if generation == 1
          encoded, decoded = reference, reference_decoded
        else
          encoded = @codec.encode(previous, @quality, @sampling, @mode, @restart)
          decoded = @codec.decode(encoded.data)
        end
        changed = previous.flatten(1).zip(decoded.image.flatten(1)).count { |a, b| a != b }
        lines << "generation #{generation} #{encoded.data.length} #{JPEG.psnr(@image.flatten, decoded.image.flatten)} #{changed}"
        previous = decoded.image
      end
      lines
    end

    def quality_search
      target = @parameters['target_bytes']
      lo, hi = 1, 100
      lines = []
      while lo < hi
        mid = (lo + hi + 1) / 2
        size = encoding(mid).data.length
        lines << "rate_control_step #{mid} #{size}"
        if size <= target
          lo = mid
        else
          hi = mid - 1
        end
      end
      size = encoding(lo).data.length
      value = JPEG.psnr(@image.flatten, decoding(lo).image.flatten)
      lines << "rate_control #{lo} #{size} #{size <= target ? 'yes' : 'no'} #{value}"
      lines
    end

    def stream_report(decoded, repaired, repaired_decoded)
      lines = decoded.segments.map { |position, name, length| "stream_segment #{position} #{name} #{length}" }
      layout = decoded.layout
      lines << "stream_image #{layout.width} #{layout.height}"
      layout.components.each { |c| lines << "stream_component #{c.identifier} #{c.h} #{c.v} #{c.tq} #{c.td} #{c.ta}" }
      decoded.quantization.keys.sort.each do |id|
        lines << "stream_quant #{id} #{DCT.zigzag(decoded.quantization[id]).join(' ')}"
      end
      decoded.tables.keys.sort.each do |key|
        table = decoded.tables[key]
        longest = table.counts.each_index.select { |i| table.counts[i].positive? }.max + 1
        lines << "stream_huffman #{key[0]} #{key[1]} symbols #{table.symbols.length} longest #{longest}"
      end
      counts = decoded.states.map { |s| s[:state] }.tally
      lines << "stream_restart #{layout.restart_interval} intervals #{layout.intervals.length} ok #{counts.fetch('ok', 0)} damaged #{counts.fetch('damaged', 0)} lost #{counts.fetch('lost', 0)}"
      layout.intervals.each_with_index do |(first, count), i|
        result = decoded.states[i]
        state = result[:state]
        if state == 'damaged'
          state += " #{result[:kind]} mcu #{result[:mcu]} offset #{result[:offset]} resync #{result[:resync]}"
        end
        lines << "stream_interval #{i} #{first} #{count} #{state}"
      end
      lines << "stream_scan_bytes #{decoded.scan_bytes}"
      identical = decoded.image == repaired_decoded.image ? 'yes' : 'no'
      lines << "repair #{repaired.data.length} #{repaired.header_bytes} #{repaired.scan_bytes} identical #{identical}"
      lines
    end

    def run
      rate_lines = rate_distortion
      reference, reference_decoded = encoding(@quality), decoding(@quality)
      block_lines, block_errors = block_statistics(reference, reference_decoded)
      report = reference_report(reference, reference_decoded, block_errors)
      report.concat(sampling_comparison)
      report.concat(generations(reference, reference_decoded))
      report.concat(quality_search)
      stream_decoded = @codec.decode(@stream)
      repaired = @codec.repair(stream_decoded)
      repaired_decoded = @codec.decode(repaired.data)
      report.concat(stream_report(stream_decoded, repaired, repaired_decoded))
      FileUtils.mkdir_p('output')
      JPEG.write_lines('output/rate_distortion.csv', rate_lines)
      ImageIO.write_ppm('output/decoded.ppm', reference_decoded.image)
      ImageIO.write_hex('output/bitstream.hex', reference.data)
      ImageIO.write_ppm('output/thumbnail.ppm', thumbnail(reference_decoded))
      JPEG.write_lines('output/huffman_tables.txt', huffman_lines(reference))
      JPEG.write_lines('output/blocks.txt', block_lines)
      ImageIO.write_ppm('output/stream_decoded.ppm', stream_decoded.image)
      ImageIO.write_hex('output/repaired.hex', repaired.data)
      JPEG.write_lines('output/report.txt', report)
    end
  end

  def self.main
    image = ImageIO.read_ppm('input/image.ppm')
    parameters = ImageIO.read_params('input/params.txt')
    codec = Codec.new(*ImageIO.read_tables('input/tables.txt'))
    Experiment.new(image, parameters, codec, ImageIO.read_hex('input/stream.hex')).run
  end
end

JPEG.main if $PROGRAM_NAME == __FILE__
