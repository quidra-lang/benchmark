require 'set'
require 'fileutils'
require_relative 'sequence_io'
require_relative 'suffix_array'
require_relative 'fm_index'
require_relative 'search'
require_relative 'sam_writer'

module Aligner
  extend self
  BASES = SuffixArray::BASES
  SYMBOLS = SuffixArray::SYMBOLS
  def ratio(numerator, denominator) = SAMWriter.ratio(numerator, denominator)

  class ReferenceText
    attr_reader :references, :offsets, :text, :reverse
    def initialize(references)
      @references = references
      offset = 0
      @offsets = references.map do |reference|
        start = offset
        offset += reference.bases.size + 1
        start
      end
      @text = references.map(&:bases).join('#') + '$'
      @reverse = @text[0...-1].reverse + '$'
    end
    def position(position)
      reference = (@offsets.bsearch_index { |offset| offset > position } || @offsets.size) - 1
      return nil if reference < 0
      offset = position - @offsets[reference]
      offset < @references[reference].bases.size ? [reference, offset] : nil
    end
    def label(position)
      located = self.position(position)
      located ? "#{@references[located[0]].name}:#{located[1] + 1}" : '*'
    end
  end

  def runs(operations)
    operations.chars.chunk(&:itself).map { |operation, group| [operation, group.size] }
  end

  def describe(reference, position, strand, operations, core, trimmed, references)
    oriented = strand == '+' ? core : SequenceIO.reverse_complement(core)
    sequence = references[reference].bases
    cigar, md, pairs = [], [], []
    i, j, matches, nm = 0, position, 0, 0
    runs(operations).each do |operation, count|
      cigar << "#{count}#{operation}"
      case operation
      when 'I'
        i += count
        nm += count
      when 'D'
        md << "#{matches}^#{sequence[j, count]}"
        matches = 0
        j += count
        nm += count
      else
        count.times do
          pairs << [i, j]
          if oriented[i] == sequence[j]
            matches += 1
          else
            md << "#{matches}#{sequence[j]}"
            matches = 0
            nm += 1
          end
          i += 1
          j += 1
        end
      end
    end
    md << matches.to_s
    unless trimmed.zero?
      strand == '+' ? cigar.push("#{trimmed}S") : cigar.unshift("#{trimmed}S")
    end
    { reference: reference, position: position, strand: strand, operations: operations,
      oriented: oriented, pairs: pairs, cigar: cigar.join, nm: nm, md: md.join }
  end

  def subtract(value, penalty) = value.nil? ? nil : value - penalty
  def maximum_reachable(*values) = values.compact.max

  def banded_alignment(oriented, sequence, center, width, scores)
    match, mismatch, gap_open, gap_extend = scores
    length, reference_length = oriented.size, sequence.size
    h, e, f = {}, {}, {}
    [0, center - width].max.upto([reference_length, center + width].min) { |j| h[[0, j]] = 0 }
    1.upto(length) do |i|
      first, last = [0, i + center - width].max, [reference_length, i + center + width].min
      first.upto(last) do |j|
        cell = [i, j]
        f[cell] = maximum_reachable(subtract(h[[i - 1, j]], gap_open + gap_extend), subtract(f[[i - 1, j]], gap_extend))
        diagonal = nil
        if j >= 1
          e[cell] = maximum_reachable(subtract(h[[i, j - 1]], gap_open + gap_extend), subtract(e[[i, j - 1]], gap_extend))
          previous = h[[i - 1, j - 1]]
          diagonal = previous + (oriented[i - 1] == sequence[j - 1] ? match : -mismatch) unless previous.nil?
        end
        h[cell] = maximum_reachable(diagonal, e[cell], f[cell])
      end
    end
    endpoints = h.filter_map { |(i, j), value| [value, j] if i == length && !value.nil? }
    return nil if endpoints.empty?
    score, j = endpoints.max_by { |value, column| [value, -column] }
    i, state, backward = length, 'H', +''
    loop do
      cell = [i, j]
      case state
      when 'H'
        break if i.zero?
        previous = j >= 1 ? h[[i - 1, j - 1]] : nil
        unless previous.nil?
          delta = oriented[i - 1] == sequence[j - 1] ? match : -mismatch
          if h[cell] == previous + delta
            backward << 'M'
            i -= 1
            j -= 1
            next
          end
        end
        state = !f[cell].nil? && h[cell] == f[cell] ? 'I' : 'D'
      when 'I'
        backward << 'I'
        previous = f[[i - 1, j]]
        state = !previous.nil? && f[cell] == previous - gap_extend ? 'I' : 'H'
        i -= 1
      when 'D'
        backward << 'D'
        previous = e[[i, j - 1]]
        state = !previous.nil? && e[cell] == previous - gap_extend ? 'D' : 'H'
        j -= 1
      end
    end
    [score, j, backward.reverse]
  end

  class Mapper
    attr_reader :search_counts, :seed_counts
    def initialize(reference_text, forward_index, reverse_index, params)
      @reference_text, @references = reference_text, reference_text.references
      @forward, @reverse, @params = forward_index, reverse_index, params
      @search_counts, @seed_counts = Hash.new(0), Hash.new(0)
    end
    def value(name) = @params.fetch(name).first
    def locate(row) = @reference_text.position(@forward.locate(row).first)
    def alignment(reference, position, strand, operations, result)
      Aligner.describe(reference, position, strand, operations, result[:core], result[:trimmed], @references)
    end

    def map_read(read)
      qualities = read.quality.bytes.map { |code| code - 33 }
      length = read.bases.size
      length -= 1 while length > 0 && qualities[length - 1] < value('TRIM_QUALITY')
      core = read.bases[0, length]
      result = { read: read, core: core, qualities: qualities, length: length,
                 trimmed: read.bases.size - length, mapped: false, reason: 'SHORT' }
      return result if length < value('MIN_READ_LENGTH')
      oriented = [core, SequenceIO.reverse_complement(core)]
      exact = oriented.map { |sequence| @forward.backward_search(sequence) }
      maximum = exact.any? { |lower, upper| lower < upper } ? 1 : value('MAX_MISMATCHES')
      hits = []
      oriented.each_with_index do |sequence, strand|
        nodes, leaves, positions = Search.backtrack(sequence, maximum, @forward, @reverse)
        @search_counts[:calls] += 1
        @search_counts[:nodes] += nodes
        @search_counts[:leaves] += leaves.size
        @search_counts[:positions] += positions
        leaves.each do |lower, upper, mismatches|
          (lower...upper).each do |row|
            reference, offset = locate(row)
            hits << [mismatches, reference, offset, strand]
          end
        end
      end
      hits.empty? ? seed_and_extend(result, oriented) : finish_search(result, hits.sort)
      result
    end

    def finish_search(result, hits)
      best = hits.first[0]
      n1 = hits.count { |hit| hit[0] == best }
      n2 = hits.count { |hit| hit[0] == best + 1 }
      alignments = hits.take_while { |hit| hit[0] <= best + 1 }.map do |_, reference, offset, strand|
        alignment(reference, offset, '+-'[strand], 'M' * result[:length], result)
      end
      mapq = if n1 >= 2
               0
             elsif n2.zero?
               60 - 12 * best
             else
               [30 - 12 * best - 3 * n2, 1].max
             end
      match, mismatch = @params['SCORES']
      targets = hits.select { |hit| hit[0] == best }.map { |hit| hit[1] }.uniq.sort
      result.merge!(mapped: true, primary: alignments.first, others: alignments.drop(1),
                    method: best.zero? ? 'EXACT' : 'MISMATCH', score: (result[:length] - best) * match - best * mismatch,
                    mapq: mapq, x0: n1, x1: n2, targets: targets)
    end

    def make_candidates(oriented)
      candidates = Set.new
      length = value('SEED_LENGTH')
      oriented.each_with_index do |sequence, strand|
        0.step(sequence.size - length, value('SEED_STEP')) do |offset|
          @seed_counts[:seeds] += 1
          seed = sequence[offset, length]
          if seed.include?('N')
            @seed_counts[:with_n] += 1
            next
          end
          lower, upper = @forward.backward_search(seed)
          if upper - lower > value('MAX_SEED_HITS')
            @seed_counts[:repetitive] += 1
          elsif lower >= upper
            @seed_counts[:without_hit] += 1
          else
            (lower...upper).each do |row|
              reference, position = locate(row)
              candidates << [strand, reference, position - offset]
            end
          end
        end
      end
      @seed_counts[:candidates] += candidates.size
      candidates.to_a.sort
    end

    def seed_and_extend(result, oriented)
      result[:reason] = 'NOHIT'
      return if result[:length] < value('SEED_LENGTH')
      @seed_counts[:reads] += 1
      accepted = {}
      scores = @params['SCORES']
      threshold = value('MIN_SCORE_PERCENT') * scores[0] * result[:length]
      make_candidates(oriented).each do |strand, reference, center|
        candidate = Aligner.banded_alignment(oriented[strand], @references[reference].bases, center, value('BAND_WIDTH'), scores)
        next if candidate.nil? || 100 * candidate[0] < threshold
        score, position, operations = candidate
        key = [reference, position, strand]
        accepted[key] = [score, operations] if !accepted.key?(key) || score > accepted[key][0]
      end
      @seed_counts[:passing] += accepted.size
      return if accepted.empty?
      ordered = accepted.map { |(reference, position, strand), (score, operations)| [score, reference, position, strand, operations] }
                        .sort_by { |score, reference, position, strand, _| [-score, reference, position, strand] }
      best = ordered.first[0]
      n1 = ordered.count { |item| item[0] == best }
      second = ordered.select { |item| item[0] < best }.map(&:first).max || 0
      alignments = ordered.map { |_, reference, position, strand, operations| alignment(reference, position, '+-'[strand], operations, result) }
      targets = ordered.select { |item| item[0] == best }.map { |item| item[1] }.uniq.sort
      result.merge!(mapped: true, primary: alignments.first, others: alignments.drop(1), method: 'SEED', score: best,
                    mapq: n1 >= 2 ? 0 : 60 * (best - second) / best, x0: n1, x1: ordered.size - n1, targets: targets)
    end
  end

  def index_statistics(reference_text, suffixes, classes, forward, reverse_suffixes, reverse_classes, reverse, params)
    text, reverse_text = reference_text.text, reference_text.reverse
    references, size = reference_text.references, text.size
    lines = ["text length #{size} sequences #{references.size}"]
    references.each_with_index do |reference, number|
      lines << "sequence #{reference.name} length #{reference.bases.size} offset #{reference_text.offsets[number]} gc #{ratio(reference.bases.count('GC'), reference.bases.size)} masked #{reference.masked}"
    end
    frequencies = Hash.new(0).merge(text.chars.tally)
    lines << 'symbols ' + SYMBOLS.chars.map { |symbol| "#{symbol} #{frequencies[symbol]}" }.join(' ')
    lines.concat(['', 'forward_index', "suffix_array rounds #{classes.size - 1}"])
    classes.each_with_index { |count, t| lines << "round #{t} prefix_length #{1 << t} classes #{count}" }
    ordered, lcp_sum, maximum, row = SuffixArray.adjacent_check(text, suffixes)
    lines << "sa_check pairs #{size - 1} ordered #{ordered} lcp_sum #{lcp_sum} mean_lcp #{ratio(lcp_sum, size - 1)} max_lcp #{maximum}"
    lines << "longest_repeat #{maximum} #{reference_text.label(suffixes[row - 1])} #{reference_text.label(suffixes[row])}"
    length = params['SEED_LENGTH'][0]
    kmers = Hash.new(0)
    references.each { |reference| 0.upto(reference.bases.size - length) { |position| kmers[reference.bases[position, length]] += 1 } }
    occurrences, unique = kmers.values.sum, kmers.values.count(1)
    lines << "kmers length #{length} occurrences #{occurrences} distinct #{kmers.size} unique #{unique} max_occurrence #{kmers.values.max} unique_fraction #{ratio(unique, occurrences)}"
    lines << "bwt runs #{runs(forward.bwt).size} head #{forward.bwt[0, 60]}"
    lines << 'c_array ' + SYMBOLS.chars.map { |symbol| "#{symbol} #{forward.c_array[symbol]}" }.join(' ')
    lines << "occ interval #{forward.interval} checkpoints #{forward.checkpoints.size}"
    lines << "sa_sample interval #{params['SA_SAMPLE_INTERVAL'][0]} samples #{forward.samples.size}"
    correct = total_steps = max_steps = 0
    suffixes.each_with_index do |position, row_number|
      located, steps = forward.locate(row_number)
      correct += 1 if located == position
      total_steps += steps
      max_steps = [max_steps, steps].max
    end
    lines << "locate rows #{size} correct #{correct} total_steps #{total_steps} max_steps #{max_steps} mean_steps #{ratio(total_steps, size)}"
    lines << "inverse_bwt identical #{forward.inverse == text ? 'yes' : 'no'}"
    reverse_ordered = SuffixArray.adjacent_check(reverse_text, reverse_suffixes)[0]
    lines.concat(['', 'reverse_index', "suffix_array rounds #{reverse_classes.size - 1}",
                  "sa_check pairs #{size - 1} ordered #{reverse_ordered}",
                  "bwt runs #{runs(reverse.bwt).size} head #{reverse.bwt[0, 60]}",
                  "inverse_bwt identical #{reverse.inverse == reverse_text ? 'yes' : 'no'}", '', 'direct_sort'])
    cross_checks = 0
    references.each do |reference|
      next unless reference.bases.size <= params['DIRECT_SORT_LIMIT'][0]
      sequence = reference.bases + '$'
      doubled, counts = SuffixArray.build(sequence)
      lines << "#{reference.name} length #{sequence.size} rounds #{counts.size - 1} identical #{doubled == SuffixArray.direct_sort(sequence) ? 'yes' : 'no'}"
      cross_checks += 1
    end
    lines << 'none' if cross_checks.zero?
    occurrence_bytes = 24 * forward.checkpoints.size
    sample_bytes = 4 * forward.samples.size
    bitmap_bytes = (size + 7) / 8
    total_bytes = size + occurrence_bytes + sample_bytes + bitmap_bytes
    lines.concat(['', "index_size bwt_bytes #{size} occ_bytes #{occurrence_bytes} sample_bytes #{sample_bytes} bitmap_bytes #{bitmap_bytes} total_bytes #{total_bytes} full_bytes #{5 * size} ratio #{ratio(total_bytes, 5 * size)}"])
    lines
  end

  def coverage_and_variants(results, references, params)
    depths = references.map { |reference| Array.new(reference.bases.size, 0) }
    starts = references.map { |reference| Array.new(reference.bases.size, 0) }
    pileups = references.map { |reference| Array.new(reference.bases.size) { Array.new(4) { [0, 0] } } }
    min_depth, min_quality, min_alt, hom_percent = params['VARIANTS']
    minimum_mapq = params['COVERAGE_MIN_MAPQ'][0]
    results.each do |result|
      next unless result[:mapped]
      alignment = result[:primary]
      reference, position = alignment.values_at(:reference, :position)
      strand = alignment[:strand] == '+' ? 0 : 1
      starts[reference][position] += 1 if result[:mapq].zero?
      next if result[:mapq] < minimum_mapq
      alignment[:pairs].each do |i, offset|
        depths[reference][offset] += 1
        base = alignment[:oriented][i]
        cycle = strand.zero? ? i + 1 : result[:length] - i
        pileups[reference][offset][BASES.index(base)][strand] += 1 if base != 'N' && result[:qualities][cycle - 1] >= min_quality
      end
    end
    window = params['COVERAGE_WINDOW'][0]
    coverage = ["window #{window} min_mapq #{minimum_mapq}"]
    variants = ["min_depth #{min_depth} min_base_quality #{min_quality} min_alt_percent #{min_alt} hom_percent #{hom_percent}"]
    callable_count = variant_count = heterozygous = homozygous = 0
    references.each_with_index do |reference, number|
      length, depth = reference.bases.size, depths[number]
      covered = depth.count(&:positive?)
      histogram = Hash.new(0).merge(depth.tally)
      coverage << "reference #{reference.name} length #{length} covered #{covered} breadth #{ratio(covered, length)} mean_depth #{ratio(depth.sum, length)} max_depth #{depth.max}"
      coverage << 'depth_histogram ' + (0..depth.max).map { |value| "#{value}:#{histogram[value]}" }.join(' ')
      0.step(length - 1, window) do |first|
        last = [first + window, length].min
        size = last - first
        values, sequence = depth[first...last], reference.bases[first...last]
        total = values.sum
        coverage << "#{reference.name} #{first + 1} #{last} gc #{ratio(sequence.count('GC'), size)} sum #{total} mean #{ratio(total, size)} max #{values.max} zero #{values.count(0)} mapq0 #{starts[number][first...last].sum} |#{'#' * (10 * total / size)}"
      end
      pileups[number].each_with_index do |strand_counts, offset|
        counts = strand_counts.map(&:sum)
        dp = counts.sum
        next if dp < min_depth
        callable_count += 1
        reference_base = reference.bases[offset]
        alternative = (0...4).reject { |base| BASES[base] == reference_base }.max_by { |base| [counts[base], -base] }
        n_alt = counts[alternative]
        next if n_alt < 2 || 100 * n_alt < min_alt * dp
        hom = 100 * n_alt >= hom_percent * dp
        if hom
          homozygous += 1
        else
          heterozygous += 1
        end
        variant_count += 1
        plus, minus = strand_counts[alternative]
        variants << "#{reference.name} #{offset + 1} #{reference_base}>#{BASES[alternative]} depth #{dp} alt #{n_alt} fraction #{ratio(n_alt, dp)} genotype #{hom ? '1/1' : '0/1'} strands #{plus} #{minus} counts #{counts.join(' ')}"
      end
    end
    variants << "callable #{callable_count} variants #{variant_count} heterozygous #{heterozygous} homozygous #{homozygous}"
    [coverage, variants]
  end

  def error_statistics(results, references)
    maximum_cycle = results.map { |result| result[:read].bases.size }.max
    cycles = Array.new(maximum_cycle + 1) { [0, 0] }
    substitutions = Array.new(4) { Array.new(5, 0) }
    quality_counts, quality_sums = [0, 0], [0, 0]
    quality_bins = Array.new(5) { [0, 0] }
    operations, events, indel_bases = Hash.new(0), Hash.new(0), Hash.new(0)
    results.each do |result|
      next unless result[:mapped]
      alignment = result[:primary]
      alignment[:operations].each_char { |operation| operations[operation] += 1 }
      operations['S'] += result[:trimmed]
      next unless result[:x0] == 1
      sequence = references[alignment[:reference]].bases
      alignment[:pairs].each do |i, offset|
        observed, reference = alignment[:oriented][i], sequence[offset]
        mismatch = observed == reference ? 0 : 1
        cycle = alignment[:strand] == '+' ? i + 1 : result[:length] - i
        quality = result[:qualities][cycle - 1]
        cycles[cycle][0] += 1
        cycles[cycle][1] += mismatch
        substitutions[BASES.index(reference)]['ACGTN'.index(observed)] += 1
        quality_counts[mismatch] += 1
        quality_sums[mismatch] += quality
        bin = [quality / 10, 4].min
        quality_bins[bin][0] += 1
        quality_bins[bin][1] += mismatch
      end
      runs(alignment[:operations]).each do |operation, count|
        next unless 'ID'.include?(operation)
        events[operation] += 1
        indel_bases[operation] += count
      end
    end
    aligned, mismatches = quality_counts.sum, quality_counts[1]
    lines = ["error_profile aligned_bases #{aligned} mismatches #{mismatches} rate #{ratio(mismatches, aligned)}", 'substitutions', 'ref A C G T N']
    BASES.chars.zip(substitutions).each { |base, counts| lines << base + ' ' + counts.join(' ') }
    lines << 'mismatch_by_cycle'
    1.upto(maximum_cycle) do |cycle|
      count, errors = cycles[cycle]
      lines << "cycle #{cycle} aligned #{count} mismatches #{errors} rate #{ratio(errors, count)}"
    end
    lines << "quality matched #{quality_counts[0]} mean #{ratio(quality_sums[0], quality_counts[0])} mismatched #{quality_counts[1]} mean #{ratio(quality_sums[1], quality_counts[1])}"
    lines << 'quality_bins'
    %w[0-9 10-19 20-29 30-39 40-].zip(quality_bins).each do |name, (count, errors)|
      lines << "#{name} aligned #{count} mismatches #{errors} rate #{ratio(errors, count)}"
    end
    lines << 'cigar ' + 'MIDS'.chars.map { |operation| "#{operation} #{operations[operation]}" }.join(' ')
    lines << "indels insertions #{events['I']} #{indel_bases['I']} deletions #{events['D']} #{indel_bases['D']}"
    lines
  end

  def mapping_statistics(results, references, search_counts, seed_counts)
    total = results.size
    mapped = results.select { |result| result[:mapped] }
    unique = mapped.count { |result| result[:x0] == 1 }
    reasons = Hash.new(0).merge(results.reject { |result| result[:mapped] }.map { |result| result[:reason] }.tally)
    methods = Hash.new(0).merge(mapped.map { |result| result[:method] }.tally)
    strands = Hash.new(0).merge(mapped.map { |result| result[:primary][:strand] }.tally)
    lines = ["reads total #{total} trimmed #{results.count { |result| result[:trimmed] > 0 }} trimmed_bases #{results.sum { |result| result[:trimmed] }} short #{reasons['SHORT']}",
             "mapped #{mapped.size} rate #{ratio(mapped.size, total)} unique #{unique} multi #{mapped.size - unique} unmapped #{total - mapped.size}",
             "unmapped short #{reasons['SHORT']} nohit #{reasons['NOHIT']}",
             "method exact #{methods['EXACT']} mismatch #{methods['MISMATCH']} seed #{methods['SEED']}",
             "strand forward #{strands['+']} reverse #{strands['-']}"]
    references.each_with_index do |reference, number|
      on_reference = mapped.select { |result| result[:primary][:reference] == number }
      forward = on_reference.count { |result| result[:primary][:strand] == '+' }
      lines << "reference #{reference.name} mapped #{on_reference.size} unique #{on_reference.count { |result| result[:x0] == 1 }} forward #{forward} reverse #{on_reference.size - forward}"
    end
    lines << 'length_bins'
    minimum, maximum = results.map { |result| result[:length] }.minmax
    (minimum / 10 * 10).step(maximum / 10 * 10, 10) do |lower|
      in_bin = results.select { |result| result[:length].between?(lower, lower + 9) }
      mapped_bin = in_bin.select { |result| result[:mapped] }
      lines << "#{lower}-#{lower + 9} reads #{in_bin.size} mapped #{mapped_bin.size} unique #{mapped_bin.count { |result| result[:x0] == 1 }}"
    end
    with_n = results.select { |result| result[:read].bases.include?('N') }
    lines << "n_reads #{with_n.size} n_bases #{with_n.sum { |result| result[:read].bases.count('N') }} mapped #{with_n.count { |result| result[:mapped] }}"
    target_counts = Hash.new(0)
    mapped.each do |result|
      next unless result[:x0] >= 2
      target_counts[result[:targets].map { |reference| references[reference].name }.join('+')] += 1
    end
    lines << 'multi_targets'
    if target_counts.empty?
      lines << 'none'
    else
      target_counts.sort.each { |names, count| lines << "#{names} #{count}" }
    end
    mapq_counts = mapped.map { |result| result[:mapq] }.tally
    nm_counts = mapped.map { |result| result[:primary][:nm] }.tally
    lines << 'mapq_histogram'
    mapq_counts.keys.sort.reverse_each { |value| lines << "#{value} #{mapq_counts[value]}" }
    lines << 'nm_histogram'
    nm_counts.sort.each { |value, count| lines << "#{value} #{count}" }
    lines.concat(error_statistics(results, references))
    lines << "search dfs_calls #{search_counts[:calls]} dfs_nodes #{search_counts[:nodes]} dfs_leaves #{search_counts[:leaves]} dfs_positions #{search_counts[:positions]}"
    lines << 'seeds ' + %i[reads seeds with_n repetitive without_hit candidates passing].map { |key| "#{key} #{seed_counts[key]}" }.join(' ')
    lines
  end

  def main
    references, reads, params = SequenceIO.read_inputs
    reference_text = ReferenceText.new(references)
    suffixes, classes = SuffixArray.build(reference_text.text)
    reverse_suffixes, reverse_classes = SuffixArray.build(reference_text.reverse)
    interval = params['OCC_INTERVAL'][0]
    forward = FMIndex.new(reference_text.text, suffixes, interval, params['SA_SAMPLE_INTERVAL'][0])
    reverse = FMIndex.new(reference_text.reverse, reverse_suffixes, interval)
    index_lines = index_statistics(reference_text, suffixes, classes, forward, reverse_suffixes, reverse_classes, reverse, params)
    mapper = Mapper.new(reference_text, forward, reverse, params)
    results = reads.map { |read| mapper.map_read(read) }
    sam_lines = SAMWriter.header(references) + results.map { |result| SAMWriter.record(result, references, params['MAX_ALT_HITS'][0]) }
    coverage_lines, variant_lines = coverage_and_variants(results, references, params)
    summary_lines = mapping_statistics(results, references, mapper.search_counts, mapper.seed_counts)
    FileUtils.mkdir_p('output')
    { 'alignments.sam' => sam_lines, 'coverage.txt' => coverage_lines, 'variants.txt' => variant_lines,
      'index_stats.txt' => index_lines, 'summary.txt' => summary_lines }.each do |filename, lines|
      SAMWriter.write_lines(File.join('output', filename), lines)
    end
  end
end

Aligner.main if __FILE__ == $PROGRAM_NAME
