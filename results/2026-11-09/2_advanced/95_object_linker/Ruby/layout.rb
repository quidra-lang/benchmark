require_relative 'object_parser'

class OutputSection
  attr_reader :name, :segment, :nobits, :sections
  attr_accessor :base_components, :components, :address, :size, :alignment

  def initialize(name, segment)
    @name, @segment, @nobits = name, segment, ObjectParser.nobits?(name)
    @sections, @base_components, @components = [], [], []
    @address, @size, @alignment = 0, 0, 1
  end
end

class Segment
  attr_reader :name, :base, :length, :fill, :outputs
  attr_accessor :paddr, :filesz, :memsz, :used, :image

  def initialize(name, base, length, fill, output_names)
    @name, @base, @length, @fill = name, base, length, fill
    @outputs = output_names.map { |output| OutputSection.new(output, self) }
    @paddr, @filesz, @memsz, @used, @image = base, 0, 0, 0, []
  end
end

module Layout
  module_function

  def align(value, alignment)
    (value + alignment - 1) / alignment * alignment
  end

  def find_output(name, outputs)
    outputs.find { |output| ObjectParser.belongs?(name, output.name) }
  end

  def assign_segment(segment)
    cursor, segment.filesz = segment.base, 0
    segment.outputs.each do |output|
      output.alignment = output.components.map(&:alignment).max || 1
      cursor = align(cursor, output.alignment)
      output.address = cursor
      output.components.each do |component|
        cursor = align(cursor, component.alignment)
        component.address = cursor
        cursor += component.size
      end
      output.size = cursor - output.address
      segment.filesz = cursor - segment.base unless output.nobits
    end
    segment.memsz = cursor - segment.base
  end
end
