module ObjectParser
  module_function

  def belongs?(name, prefix)
    name == prefix || name.start_with?(prefix + '.')
  end

  def nobits?(name)
    belongs?(name, '.bss')
  end

  def string_section?(name)
    belongs?(name, '.rodata.str')
  end

  def read_lines(path)
    File.binread(path).lines(chomp: true)
  end

  def parse(lines, index, name)
    object = LinkObject.new(name)
    until lines[index] == 'end'
      words = lines[index].split(' ')
      index += 1
      case words[0]
      when 'section'
        section = InputSection.new(object, words[1], words[2].to_i, words[3].to_i)
        object.sections << section
        object.section_names[section.name] = section
        unless section.nobits
          while section.contents.length < section.size
            section.contents.concat([lines[index].split(' ')[1]].pack('H*').bytes)
            index += 1
          end
        end
      when 'comdat'
        object.comdats << [words[1], words.drop(2).map { |section_name| object.section_names.fetch(section_name) }]
      when 'symbol'
        kind = {'undef' => 'undefined', 'common' => 'common'}.fetch(words[3], 'defined')
        symbol = SymbolEntry.new(object, words[1], words[2], kind)
        if kind == 'defined'
          symbol.section, symbol.offset = object.section_names.fetch(words[3]), words[4].to_i
        elsif kind == 'common'
          symbol.size, symbol.alignment = words[4].to_i, words[5].to_i
        end
        object.symbols << symbol
        object.symbol_names[symbol.name] = symbol
      when 'reloc'
        section = object.section_names.fetch(words[1])
        section.relocations << Relocation.new(section, words[2].to_i, words[3],
                                              object.symbol_names.fetch(words[4]), words[5].to_i)
      end
    end
    [object, index + 1]
  end

  def read_object(path)
    parse(read_lines(path), 0, File.basename(path))[0]
  end
end

class InputSection
  attr_reader :kind, :owner, :name, :alignment, :size, :nobits, :string, :relocations, :merged_positions
  attr_accessor :contents, :discard_reason, :output, :live, :address, :merged

  def initialize(owner, name, alignment, size)
    @kind, @owner, @name, @alignment, @size = 'input', owner, name, alignment, size
    @nobits, @string = ObjectParser.nobits?(name), ObjectParser.string_section?(name)
    @contents, @relocations, @merged_positions = [], [], {}
    @discard_reason = @output = @address = @merged = nil
    @live = false
  end
end

class SymbolEntry
  attr_reader :owner, :binding
  attr_accessor :name, :kind, :section, :offset, :size, :alignment

  def initialize(owner, name, binding, kind)
    @owner, @name, @binding, @kind = owner, name, binding, kind
    @section, @offset, @size, @alignment = nil, 0, 0, 1
  end
end

class Relocation
  attr_reader :section, :offset, :type, :symbol, :addend
  attr_accessor :place, :unpaired, :symbol_value, :value, :field, :status

  def initialize(section, offset, type, symbol, addend)
    @section, @offset, @type, @symbol, @addend = section, offset, type, symbol, addend
  end
end

class LinkObject
  attr_reader :name, :sections, :section_names, :comdats, :symbols
  attr_accessor :order, :symbol_names

  def initialize(name)
    @name = name
    @sections, @comdats, @symbols = [], [], []
    @section_names, @symbol_names = {}, {}
  end
end
