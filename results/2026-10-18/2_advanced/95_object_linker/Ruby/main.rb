require 'set'
require_relative 'object_parser'
require_relative 'archive'
require_relative 'resolver'
require_relative 'layout'
require_relative 'relocator'

class Script
  attr_reader :entry, :gc, :segments, :segment_names, :outputs, :output_names, :loads, :kept,
              :sorted, :wrapped, :defines, :script_names, :checksum, :inputs

  def initialize(lines)
    @segments, @loads, @defines, @inputs = [], [], [], []
    @kept, @sorted, @wrapped = Set.new, Set.new, Set.new
    @checksum = nil
    lines.each do |line|
      if line.start_with?('define ')
        head, expression = line.split(' = ', 2)
        @defines << [head.split(' ')[1], expression]
        next
      end
      words = line.split(' ')
      case words[0]
      when 'entry' then @entry = words[1]
      when 'gc' then @gc = words[1] == 'on'
      when 'segment'
        @segments << Segment.new(words[1], words[2].to_i(16), words[3].to_i(16), words[4].to_i(16), words.drop(5))
      when 'load' then @loads << words[1, 2]
      when 'keep' then @kept << words[1]
      when 'sort' then @sorted << words[1]
      when 'wrap' then @wrapped << words[1]
      when 'checksum' then @checksum = words[1, 2]
      else @inputs << [words[0], words.drop(1)]
      end
    end
    @segment_names = segments.to_h { |segment| [segment.name, segment] }
    @outputs = segments.flat_map(&:outputs)
    @output_names = outputs.to_h { |output| [output.name, output] }
    @script_names = defines.map(&:first).to_set
  end
end

class MergedStrings
  attr_reader :kind, :sections, :alignment, :contents, :strings, :size, :unique, :saved
  attr_accessor :address

  def initialize(sections)
    @kind, @sections, @alignment, @address = 'merged', sections, 1, 0
    @contents, positions, @strings = [], {}, 0
    sections.each do |section|
      section.merged = self
      start = 0
      while start < section.size
        ending = start
        ending += 1 until section.contents[ending].zero?
        ending += 1
        string = section.contents[start...ending]
        unless positions.key?(string)
          positions[string.freeze] = contents.length
          contents.concat(string)
        end
        section.merged_positions[start] = positions[string]
        @strings += 1
        start = ending
      end
    end
    @size, @unique = contents.length, positions.length
    @saved = sections.sum(&:size) - size
  end
end

class Veneer
  attr_reader :kind, :output, :name, :size, :alignment
  attr_accessor :address

  def initialize(output, name)
    @kind, @output, @name = 'veneer', output, name
    @size, @alignment, @address = 8, 4, 0
  end
end

# The script syntax is guaranteed valid; recursive descent mirrors Section 10.
class ScriptExpression
  def initialize(text, outputs, values)
    @tokens = text.scan(/0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+-]/)
    @index, @outputs, @values = 0, outputs, values
  end

  def take
    token = @tokens[@index]
    @index += 1
    token
  end

  def expression
    value = term
    while %w[+ -].include?(@tokens[@index])
      operator, right = take, term
      value = operator == '+' ? value + right : value - right
    end
    value
  end

  def term
    token = take
    if token == '('
      value = expression
      take
      return value
    end
    return token.start_with?('0x') ? token.to_i(16) : token.to_i if token.match?(/\A[0-9]/)
    return @values.fetch(token) unless @tokens[@index] == '('
    take
    if token == 'align'
      value = expression
      take
      alignment = expression
      take
      return Layout.align(value, alignment)
    end
    output = @outputs.fetch(take)
    take
    case token
    when 'start' then output.address
    when 'end' then output.address + output.size
    when 'size' then output.size
    when 'loadaddr' then output.segment.paddr + output.address - output.segment.base
    end
  end
end

class Linker
  def initialize(script)
    @script, @objects, @entries = script, [], {}
    @archives, @comdats, @extractions = {}, {}, []
    @orphans, @script_values, @veneers = Hash.new(0), {}, {}
    @far_calls, @applied = Set.new, []
    @relocation_counts = Relocator::TYPES.to_h { |type| [type, Hash.new(0)] }
  end

  def name_defined?(name)
    @script.script_names.include?(name) || @entries.fetch(name, []).any? { |entry| %w[defined common].include?(entry.kind) }
  end

  def undefined?(name)
    !name_defined?(name) && (name == @script.entry || @entries.fetch(name, []).any? { |entry| entry.kind == 'undefined' && entry.binding == 'global' })
  end

  def load_object(object)
    object.order = @objects.length
    object.comdats.each do |signature, sections|
      if @comdats.key?(signature)
        @comdats[signature][1] << object.name
        sections.each { |section| section.discard_reason = 'comdat' }
      else
        @comdats[signature] = [object.name, []]
      end
    end
    object.symbols.each do |symbol|
      if symbol.binding != 'local' && symbol.kind == 'defined' && symbol.section.discard_reason == 'comdat'
        symbol.kind, symbol.section = 'undefined', nil
      end
    end
    object.symbols.each do |symbol|
      next unless symbol.kind == 'undefined'
      if @script.wrapped.include?(symbol.name)
        symbol.name = '__wrap_' + symbol.name
      elsif symbol.name.start_with?('__real_') && @script.wrapped.include?(symbol.name[7..])
        symbol.name = symbol.name[7..]
      end
    end
    object.symbol_names = object.symbols.to_h { |symbol| [symbol.name, symbol] }
    object.symbols.each do |symbol|
      (@entries[symbol.name] ||= []) << symbol unless symbol.binding == 'local'
    end
    @objects << object
  end

  def extract(object, reason)
    reference = @entries.fetch(reason, []).find { |entry| entry.kind == 'undefined' && entry.binding == 'global' }
    @extractions << [object.name, reference ? reference.owner.name : '*entry*', reason]
    load_object(object)
  end

  def scan_archive(name)
    members = @archives[name] ||= Archive.read(File.join('input', name))
    Archive.scan(members, method(:undefined?), method(:extract))
  end

  def load_inputs
    @script.inputs.each do |kind, names|
      case kind
      when 'object' then load_object(ObjectParser.read_object(File.join('input', names[0])))
      when 'library' then scan_archive(names[0])
      when 'group'
        loop { break if names.sum { |name| scan_archive(name) }.zero? }
      end
    end
    @names = Resolver.resolve(@entries, @script.script_names)
    @commons = @names.values.select { |resolution| resolution.kind == 'common' }
  end

  def assign_outputs
    @candidates = []
    @objects.each do |object|
      object.sections.each do |section|
        next if section.discard_reason == 'comdat'
        section.output = Layout.find_output(section.name, @script.outputs)
        if section.output
          section.output.sections << section
          @candidates << section
        else
          section.discard_reason = 'orphan'
          @orphans[section.name] += 1
        end
      end
    end
  end

  def target(symbol)
    return symbol.section if symbol.binding == 'local'
    resolution = @names.fetch(symbol.name)
    return resolution.definition.section if %w[global weak].include?(resolution.kind)
    resolution if resolution.kind == 'common'
  end

  def collect_garbage
    units = (@candidates + @commons).to_set
    if !@script.gc
      units.each { |unit| unit.live = true }
    else
      pending = @candidates.select { |section| @script.kept.include?(section.output.name) }
      entry = @names[@script.entry]
      if entry
        pending << entry.definition.section if %w[global weak].include?(entry.kind)
        pending << entry if entry.kind == 'common'
      end
      until pending.empty?
        unit = pending.pop
        next unless units.include?(unit) && !unit.live
        unit.live = true
        pending.concat(unit.relocations.map { |relocation| target(relocation.symbol) }) if unit.kind == 'input'
      end
    end
    @candidates.each { |section| section.discard_reason = 'gc' unless section.live }
    @objects.each do |object|
      unresolved = Set.new
      object.sections.each do |section|
        next unless section.live
        section.relocations.each do |relocation|
          symbol = relocation.symbol
          unresolved << symbol.name if symbol.binding != 'local' && @names.fetch(symbol.name).kind == 'undefined'
        end
      end
      unresolved.each { |name| @names.fetch(name).unresolved_referrers << object.name }
    end
  end

  def build_components
    @script.outputs.each do |output|
      sections = output.sections.select(&:live)
      if @script.sorted.include?(output.name)
        sections = sections.each_with_index.sort_by do |section, index|
          priority = section.name == output.name ? 65536 : section.name[(output.name.length + 1)..].to_i
          [priority, index]
        end.map(&:first)
      end
      strings = sections.select(&:string)
      merged = MergedStrings.new(strings) unless strings.empty?
      components, inserted = [], false
      sections.each do |section|
        if section.string
          components << merged unless inserted
          inserted = true
        else
          components << section
        end
      end
      if output.name == '.bss'
        components.concat(@commons.select(&:live).sort_by { |common| [-common.alignment, common.name] })
      end
      output.base_components = components
    end
  end

  def location_address(section, offset)
    section.string ? section.merged.address + section.merged_positions.fetch(offset) : section.address + offset
  end

  def definition_address(resolution)
    definition = resolution.definition
    location_address(definition.section, definition.offset)
  end

  def find_far_calls
    calls = Set.new
    @candidates.each do |section|
      next unless section.live
      section.relocations.each do |relocation|
        symbol = relocation.symbol
        next unless relocation.type == 'CALL24' && symbol.binding != 'local'
        resolution = @names.fetch(symbol.name)
        next unless %w[global weak].include?(resolution.kind)
        value = definition_address(resolution) + relocation.addend - section.address - relocation.offset
        calls << relocation unless (-(2**25)...2**25).cover?(value)
      end
    end
    calls
  end

  def perform_layout
    build_components
    loop do
      @script.outputs.each do |output|
        veneers = @veneers.values.select { |veneer| veneer.output.equal?(output) }.sort_by(&:name)
        output.components = output.base_components + veneers
      end
      @script.segments.each { |segment| Layout.assign_segment(segment) }
      far_calls = find_far_calls
      new_pairs = far_calls.map { |relocation| [relocation.section.output, relocation.symbol.name] }.uniq.reject { |pair| @veneers.key?(pair) }
      if new_pairs.empty?
        @far_calls = far_calls
        break
      end
      new_pairs.each { |output, name| @veneers[[output, name]] = Veneer.new(output, name) }
    end
  end

  def load_addresses
    storage = @script.segments.to_h { |segment| [segment.name, segment.base + segment.memsz] }
    @script.loads.each do |source, destination|
      segment = @script.segment_names.fetch(source)
      segment.paddr = Layout.align(storage.fetch(destination), 4)
      storage[destination] = segment.paddr + segment.filesz
    end
    @script.segments.each { |segment| segment.used = storage.fetch(segment.name) - segment.base }
  end

  def evaluate_defines
    @script.defines.each do |name, text|
      @script_values[name] = ScriptExpression.new(text, @script.output_names, @script_values).expression
    end
  end

  def symbol_value(symbol)
    return location_address(symbol.section, symbol.offset) if symbol.binding == 'local'
    resolution = @names.fetch(symbol.name)
    case resolution.kind
    when 'global', 'weak' then definition_address(resolution)
    when 'common' then resolution.address
    when 'script' then @script_values.fetch(resolution.name)
    when 'weakundef' then 0
    end
  end

  def entry_address
    entry = @names[@script.entry]
    return 0 unless entry
    return definition_address(entry) if %w[global weak].include?(entry.kind)
    entry.kind == 'common' ? entry.address : 0
  end

  def little_endian(value, width)
    Array.new(width) { |index| value / 256**index % 256 }
  end

  def apply_relocations
    gp = @script_values.fetch('_gp', 0)
    @script.outputs.each do |output|
      output.components.each do |section|
        next unless section.kind == 'input'
        section.relocations.each_with_index do |relocation, index|
          relocation.place = section.address + relocation.offset
          relocation.unpaired = Relocator.unpaired_hi16?(section.relocations, index)
          relocation.symbol_value = symbol_value(relocation.symbol)
          if relocation.symbol_value.nil?
            relocation.status = 'undefined'
          else
            relocation.status = 'ok'
            if @far_calls.include?(relocation)
              relocation.symbol_value = @veneers.fetch([output, relocation.symbol.name]).address
              relocation.status = 'veneer'
            end
            value, field, within_range = Relocator.calculate(relocation.type, relocation.symbol_value, relocation.addend, relocation.place, gp)
            relocation.value, relocation.field = value, field
            relocation.status = 'overflow' unless within_range
            width = Relocator::WIDTHS.fetch(relocation.type)
            section.contents[relocation.offset, width] = little_endian(field, width)
          end
          @relocation_counts.fetch(relocation.type)[relocation.status] += 1
          @applied << relocation
        end
      end
    end
  end

  def build_images
    @script.segments.each do |segment|
      segment.image = Array.new(segment.filesz, segment.fill)
      segment.outputs.each do |output|
        next if output.nobits
        output.components.each do |component|
          contents = if component.kind == 'veneer'
                       [4, 240, 31, 229] + little_endian(definition_address(@names.fetch(component.name)), 4)
                     else
                       component.contents
                     end
          segment.image[component.address - segment.base, component.size] = contents
        end
      end
    end
    return unless @script.checksum
    segment_name, symbol_name = @script.checksum
    segment = @script.segment_names.fetch(segment_name)
    offset = definition_address(@names.fetch(symbol_name)) - segment.base
    segment.image[offset, 4] = [0, 0, 0, 0]
    total = segment.image.each_slice(4).sum { |bytes| bytes.each_with_index.sum { |byte, index| byte * 256**index } }
    segment.image[offset, 4] = little_endian(-total % 2**32, 4)
  end

  def symbol_rows
    rows = []
    @names.each do |name, resolution|
      if %w[global weak].include?(resolution.kind) && resolution.definition.section.live
        rows << [definition_address(resolution), name, resolution.kind, resolution.definer]
      elsif resolution.kind == 'common' && resolution.live
        rows << [resolution.address, name, 'common', resolution.definer]
      elsif resolution.kind == 'script'
        rows << [@script_values.fetch(name), name, 'script', '*script*']
      end
    end
    @script.outputs.each do |output|
      output.components.each do |component|
        rows << [component.address, '__veneer_' + component.name, 'veneer', '*linker*'] if component.kind == 'veneer'
      end
    end
    rows.sort_by { |address, name, _kind, _definer| [address, name] }
  end

  def relocation_location(relocation)
    "#{relocation.section.owner.name} #{relocation.section.name}+#{relocation.offset}"
  end

  def diagnostics
    lines = @orphans.keys.sort.map { |name| "warning: orphan section #{name} discarded from #{@orphans[name]} object(s)" }
    @names.each do |name, resolution|
      if resolution.strong_definers.length >= 2
        lines << "error: multiple definition of #{name}: #{resolution.strong_definers.join(' ')}"
      end
      if !resolution.commons.empty? && %w[global script].include?(resolution.kind)
        lines << "warning: common symbol #{name} overridden by #{resolution.definer}"
      end
      pairs = resolution.commons.map { |entry| [entry.size, entry.alignment] }.uniq
      if resolution.kind == 'common' && pairs.length >= 2
        lines << "warning: common symbol #{name} merged to size #{resolution.size} align #{resolution.alignment}"
      end
    end
    entry = @names[@script.entry]
    lines << "error: entry symbol #{@script.entry} is undefined" if !entry || %w[undefined weakundef].include?(entry.kind)
    @names.each do |name, resolution|
      if resolution.kind == 'undefined' && !resolution.unresolved_referrers.empty?
        lines << "error: undefined symbol #{name} referenced by #{resolution.unresolved_referrers.join(' ')}"
      end
    end
    @script.segments.each do |segment|
      if segment.used > segment.length
        lines << "error: segment #{segment.name} overflows its length by #{segment.used - segment.length} bytes"
      end
    end
    @script.segments.each_with_index do |first, index|
      @script.segments.drop(index + 1).each do |second|
        if first.memsz.positive? && second.memsz.positive? && first.base < second.base + second.memsz && second.base < first.base + first.memsz
          lines << "error: segments #{first.name} and #{second.name} overlap"
        end
      end
    end
    @applied.each do |relocation|
      location = relocation_location(relocation)
      lines << "error: unpaired HI16 at #{location} against #{relocation.symbol.name}" if relocation.unpaired
      if relocation.status == 'overflow'
        lines << "error: relocation overflow at #{location}: #{relocation.type} value #{relocation.value} against #{relocation.symbol.name}"
      end
    end
    lines << "errors #{lines.count { |line| line.start_with?('error:') }} warnings #{lines.count { |line| line.start_with?('warning:') }}"
  end

  def segment_heading(segment)
    format('segment %s vaddr %08x paddr %08x filesz %d memsz %d', segment.name, segment.base, segment.paddr, segment.filesz, segment.memsz)
  end

  def image_dump
    lines = [format('entry %08x %s', entry_address, @script.entry)]
    @script.segments.each do |segment|
      lines << segment_heading(segment)
      segment.image.each_slice(16).with_index do |bytes, index|
        lines << format('%08x ', segment.base + index * 16) + bytes.map { |byte| format('%02x', byte) }.join(' ')
      end
    end
    lines
  end

  def hex_record(type, address, data)
    record = [data.length, address / 256, address % 256, type] + data
    record << -record.sum % 256
    ':' + record.map { |byte| format('%02X', byte) }.join
  end

  def intel_hex
    lines, upper = [], 0
    segments = @script.segments.each_with_index.sort_by { |segment, index| [segment.paddr, index] }.map(&:first)
    segments.each do |segment|
      start = 0
      while start < segment.filesz
        address = segment.paddr + start
        count = [16, segment.filesz - start, 65536 - address % 65536].min
        if address / 65536 != upper
          upper = address / 65536
          lines << hex_record(4, 0, [upper / 256, upper % 256])
        end
        lines << hex_record(0, address % 65536, segment.image[start, count])
        start += count
      end
    end
    lines << hex_record(5, 0, little_endian(entry_address, 4).reverse)
    lines << hex_record(1, 0, [])
  end

  def component_line(component)
    case component.kind
    when 'input'
      format('input %08x %d %d %s %s', component.address, component.size, component.alignment, component.owner.name, component.name)
    when 'merged'
      format('merged %08x %d sections %d strings %d unique %d saved %d', component.address, component.size,
             component.sections.length, component.strings, component.unique, component.saved)
    when 'common'
      format('common %08x %d %d %s %s', component.address, component.size, component.alignment, component.definer, component.name)
    when 'veneer'
      format('veneer %08x 8 %s', component.address, component.name)
    end
  end

  def link_map
    lines = @extractions.map { |name, referrer, reason| "member #{name} #{referrer} #{reason}" }
    @comdats.each do |signature, (keeper, discarded)|
      lines << "comdat #{signature} #{keeper} #{discarded.empty? ? '-' : discarded.join(',')}"
    end
    @script.segments.each do |segment|
      lines << segment_heading(segment) + " used #{segment.used} length #{segment.length} #{100 * segment.used / segment.length}%"
      segment.outputs.each do |output|
        lines << format('section %s %08x %d %d', output.name, output.address, output.size, output.alignment)
        lines.concat(output.components.map { |component| component_line(component) })
      end
    end
    @objects.each do |object|
      object.sections.each do |section|
        lines << "discard #{object.name} #{section.name} #{section.size} #{section.discard_reason}" if section.discard_reason
      end
    end
    @commons.sort_by(&:name).each do |common|
      lines << "discard #{common.definer} COMMON(#{common.name}) #{common.size} gc" unless common.live
    end
    symbol_rows.each { |address, name, kind, definer| lines << format('symbol %08x %s %s %s', address, name, kind, definer) }
    lines
  end

  def cross_references
    @names.map do |name, resolution|
      status = case resolution.kind
               when 'global', 'weak' then resolution.definition.section.live ? 'kept' : 'discarded'
               when 'common' then resolution.live ? 'kept' : 'discarded'
               when 'script' then 'kept'
               else '-'
               end
      referrers = resolution.referrers.empty? ? '-' : resolution.referrers.join(',')
      "#{name} #{resolution.kind} #{status} #{resolution.definer} #{referrers}"
    end
  end

  def relocation_report
    lines = @applied.map do |relocation|
      prefix = format('%08x %s %s %s %d', relocation.place, relocation_location(relocation), relocation.type, relocation.symbol.name, relocation.addend)
      values = if relocation.status == 'undefined'
                 '- - -'
               else
                 digits = Relocator::WIDTHS.fetch(relocation.type) * 2
                 format('%08x %d %0*x', relocation.symbol_value, relocation.value, digits, relocation.field)
               end
      "#{prefix} #{values} #{relocation.status}"
    end
    Relocator::TYPES.each do |type|
      counts = @relocation_counts.fetch(type)
      lines << "summary #{type} total #{counts.values.sum} ok #{counts['ok']} veneer #{counts['veneer']} overflow #{counts['overflow']} undefined #{counts['undefined']}"
    end
    lines
  end

  def run
    load_inputs
    assign_outputs
    collect_garbage
    perform_layout
    load_addresses
    evaluate_defines
    apply_relocations
    build_images
    reports = {'image.hex' => image_dump, 'flash.ihex' => intel_hex, 'link.map' => link_map,
               'xref.txt' => cross_references, 'relocations.txt' => relocation_report, 'diagnostics.txt' => diagnostics}
    Dir.mkdir('output') unless Dir.exist?('output')
    reports.each { |name, lines| File.binwrite(File.join('output', name), lines.map { |line| line + "\n" }.join) }
  end
end

Linker.new(Script.new(ObjectParser.read_lines('input/link.txt'))).run if $PROGRAM_NAME == __FILE__
