require_relative 'sequence_io'

module SAMWriter
  def self.ratio(numerator, denominator)
    denominator.zero? ? '-' : format('%.4f', numerator.fdiv(denominator))
  end
  def self.header(references)
    ["@HD\tVN:1.6\tSO:unsorted",
     *references.map { |reference| "@SQ\tSN:#{reference.name}\tLN:#{reference.bases.size}" },
     "@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0"]
  end
  def self.record(result, references, maximum_alternatives)
    read = result[:read]
    unless result[:mapped]
      return [read.name, 4, '*', 0, 0, '*', '*', 0, 0, read.bases, read.quality, 'YM:Z:' + result[:reason]].join("\t")
    end
    alignment = result[:primary]
    reverse = alignment[:strand] == '-'
    fields = [read.name, reverse ? 16 : 0, references[alignment[:reference]].name,
              alignment[:position] + 1, result[:mapq], alignment[:cigar], '*', 0, 0,
              reverse ? SequenceIO.reverse_complement(read.bases) : read.bases,
              reverse ? read.quality.reverse : read.quality,
              "NM:i:#{alignment[:nm]}", "MD:Z:#{alignment[:md]}", "AS:i:#{result[:score]}",
              "X0:i:#{result[:x0]}", "X1:i:#{result[:x1]}", "YM:Z:#{result[:method]}"]
    others = result[:others]
    if others.size.between?(1, maximum_alternatives)
      alternatives = others.map do |item|
        "#{references[item[:reference]].name},#{item[:strand]}#{item[:position] + 1},#{item[:cigar]},#{item[:nm]};"
      end.join
      fields << 'XA:Z:' + alternatives
    end
    fields.join("\t")
  end
  def self.write_lines(path, lines)
    File.write(path, lines.join("\n") + (lines.empty? ? '' : "\n"))
  end
end
