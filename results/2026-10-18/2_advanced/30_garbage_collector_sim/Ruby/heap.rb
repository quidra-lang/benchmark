module GCSim
  class HeapObject
    attr_reader :number, :size, :fields
    attr_accessor :address, :marked, :moves, :age, :count

    def initialize(number, pointers, data)
      @number = number
      @size = 1 + pointers + data
      @fields = Array.new(pointers)
      @address = @moves = @age = @count = 0
      @marked = false
    end
  end

  class Pair
    attr_reader :count, :words

    def initialize(objects = [])
      @count = @words = 0
      objects.each { |obj| add(obj) }
    end

    def add(obj)
      @count += 1
      @words += obj.size
      self
    end

    def merge(other)
      @count += other.count
      @words += other.words
      self
    end

    def to_s = "#{@count} #{@words}"
  end

  module HeapTools
    extend self

    SIZE_CLASSES = %w[1 2-3 4-7 8-15 16+].freeze
    SIZE_LIMITS = [1, 3, 7, 15].freeze

    def by_address(objects) = objects.sort_by(&:address)
    def total_free(blocks) = blocks.sum { |_, length| length }
    def largest_free(blocks) = blocks.map(&:last).max || 0
    def free_stats(blocks) = [total_free(blocks), largest_free(blocks)]

    def free_blocks(objects, first, limit)
      blocks = []
      position = first
      by_address(objects).each do |obj|
        next unless obj.address >= first && obj.address < limit

        blocks << [position, obj.address - position] if obj.address > position
        position = obj.address + obj.size
      end
      blocks << [position, limit - position] if position < limit
      blocks
    end

    def first_fit(blocks, size)
      blocks.find { |_, length| length >= size }&.first
    end

    def dec2(numerator, denominator)
      rounded = (200 * numerator + denominator) / (2 * denominator)
      format('%d.%02d', rounded / 100, rounded % 100)
    end

    def pct(part, whole) = whole.zero? ? '-' : dec2(100 * part, whole)

    def class_table(values)
      counts = Array.new(SIZE_CLASSES.length, 0)
      values.each do |value|
        index = SIZE_LIMITS.index { |limit| value <= limit } || SIZE_LIMITS.length
        counts[index] += 1
      end
      SIZE_CLASSES.zip(counts).map { |label, count| "#{label}:#{count}" }.join(' ')
    end

    def heap_map(size, objects, reachable, inactive)
      cells = Array.new(size, '.')
      first, limit = inactive
      (first...limit).each { |address| cells[address] = '-' }
      objects.each do |obj|
        letter = (65 + (obj.number - 1) % 26).chr
        header, body = reachable.include?(obj.number) ? [letter, letter.downcase] : ['#', '=']
        cells[obj.address] = header
        (obj.address + 1...obj.address + obj.size).each { |address| cells[address] = body }
      end
      cells.join
    end
  end

  class CollectionRecord
    include HeapTools
    attr_reader :number, :line, :request, :kind, :live, :freed, :moved, :promoted,
                :before, :after
    attr_accessor :stack, :work

    def initialize(number, line, request, kind, blocks)
      @number, @line, @request, @kind = number, line, request, kind
      @live, @freed, @moved, @promoted = Array.new(4) { Pair.new }
      @stack = @work = 0
      @before = free_stats(blocks)
      @after = [0, 0]
    end

    def finish(blocks)
      @after = free_stats(blocks)
    end
  end

  class HeapState
    include HeapTools
    attr_reader :size, :objects, :records

    def initialize(size)
      @size = size
      @objects = []
      @records = []
    end

    def free_list = free_blocks(@objects, 0, @size)
    def inactive_range = [0, 0]

    def new_record(line, request, kind)
      CollectionRecord.new(@records.length + 1, line, request, kind, free_list)
    end

    def finish_record(record)
      record.finish(free_list)
      @records << record
    end
  end
end
