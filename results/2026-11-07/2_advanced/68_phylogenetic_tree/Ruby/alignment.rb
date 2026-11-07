module Alignment
  BASES = 'ACGT'
  AMBIGUOUS = 'RYSWKMBDHV'
  BASE_SETS = { 'A'=>1, 'C'=>2, 'G'=>4, 'T'=>8, 'R'=>5, 'Y'=>10,
                'S'=>6, 'W'=>9, 'K'=>12, 'M'=>3, 'B'=>14, 'D'=>13,
                'H'=>11, 'V'=>7, 'N'=>15, '-'=>15 }.freeze

  def self.read_fasta(path = 'input/alignment.fasta')
    records = []
    File.foreach(path).with_index(1) do |line, number|
      line = line.chomp
      if line.start_with?('>')
        records << [number, line[1..].split(' ', 2).first, +'']
      else
        records.last[2] << line.upcase
      end
    end
    records
  end

  class Patterns
    attr_reader :patterns, :columns, :weights, :encoded
    def initialize(sequences)
      @patterns, @columns, @weights = [], [], []
      numbers = {}
      sequences.first.size.times do |column|
        pattern = sequences.map { |sequence| sequence[column] }.join
        unless numbers.key?(pattern)
          numbers[pattern] = @patterns.size
          @patterns << pattern
          @weights << 0
        end
        index = numbers[pattern]
        @columns << index
        @weights[index] += 1
      end
      @encoded = @patterns.map { |pattern| pattern.chars.map { |char| BASE_SETS.fetch(char) } }
    end
  end

  def self.classify_columns(sequences)
    totals = %w[constant variable informative gapped empty].to_h { |key| [key, 0] }
    sequences.first.size.times do |column|
      chars = sequences.map { |sequence| sequence[column] }
      counts = chars.select { |char| BASES.include?(char) }.tally
      kind = counts.empty? ? 'empty' : counts.size == 1 ? 'constant' : 'variable'
      totals[kind] += 1
      totals['informative'] += 1 if counts.values.count { |count| count >= 2 } >= 2
      totals['gapped'] += 1 if chars.include?('-')
    end
    totals
  end
end
