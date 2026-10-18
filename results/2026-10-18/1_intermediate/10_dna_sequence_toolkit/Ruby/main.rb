BASES = 'ACGT'.freeze
IUPAC = {
  'A' => 'A', 'C' => 'C', 'G' => 'G', 'T' => 'T', 'R' => 'AG',
  'Y' => 'CT', 'W' => 'AT', 'S' => 'CG', 'K' => 'GT', 'M' => 'AC',
  'B' => 'CGT', 'D' => 'AGT', 'H' => 'ACT', 'V' => 'ACG', 'N' => 'ACGT'
}.freeze
SYMBOL = IUPAC.invert.freeze
COMPLEMENT = 'ACGTRYWSKMBVDHN'.chars.zip('TGCAYRWSMKVBHDN'.chars).to_h.freeze
GROUPS = {
  'A' => 'GCT GCC GCA GCG', 'C' => 'TGT TGC', 'D' => 'GAT GAC',
  'E' => 'GAA GAG', 'F' => 'TTT TTC', 'G' => 'GGT GGC GGA GGG',
  'H' => 'CAT CAC', 'I' => 'ATT ATC ATA', 'K' => 'AAA AAG',
  'L' => 'TTA TTG CTT CTC CTA CTG', 'M' => 'ATG', 'N' => 'AAT AAC',
  'P' => 'CCT CCC CCA CCG', 'Q' => 'CAA CAG',
  'R' => 'CGT CGC CGA CGG AGA AGG', 'S' => 'TCT TCC TCA TCG AGT AGC',
  'T' => 'ACT ACC ACA ACG', 'V' => 'GTT GTC GTA GTG', 'W' => 'TGG',
  'Y' => 'TAT TAC', '*' => 'TAA TAG TGA'
}.freeze
CODE = GROUPS.flat_map { |amino, codons| codons.split.map { |c| [c, amino] } }.to_h.freeze
AMINO_MASS = 'ACDEFGHIKLMNPQRSTVWY'.chars.zip([
  71079, 103139, 115089, 129116, 147177, 57052, 137141, 113160, 128174, 113160,
  131193, 114104, 97117, 128131, 156188, 87078, 101105, 99133, 186213, 163176
]).to_h.freeze
BASE_MASS = BASES.chars.zip([331222, 307197, 347221, 322208]).to_h.freeze
ENZYMES = {
  'EcoRI' => ['GAATTC', 1], 'BamHI' => ['GGATCC', 1],
  'HindIII' => ['AAGCTT', 1], 'PstI' => ['CTGCAG', 5],
  'SmaI' => ['CCCGGG', 3], 'KpnI' => ['GGTACC', 5],
  'XbaI' => ['TCTAGA', 1], 'NotI' => ['GCGGCCGC', 2],
  'EcoRV' => ['GATATC', 3], 'HaeIII' => ['GGCC', 2],
  'AluI' => ['AGCT', 2], 'TaqI' => ['TCGA', 1],
  'Sau3AI' => ['GATC', 0], 'HincII' => ['GTYRAC', 3],
  'AvaI' => ['CYCGRG', 1]
}.freeze
ARITY = {
  'SEQ' => [2, 2], 'SLICE' => [4, 4], 'JOIN' => [3, 9], 'MUTATE' => [3, 3],
  'DEL' => [1, 1], 'LIST' => [0, 0], 'REVCOMP' => [1, 1], 'COMPLEMENT' => [1, 1],
  'REVERSE' => [1, 1], 'TRANSCRIBE' => [1, 1], 'TRANSLATE' => [2, 2],
  'CODONS' => [2, 2], 'PROTEIN' => [2, 2], 'ORFS' => [2, 2], 'GC' => [1, 1],
  'GCWINDOW' => [3, 3], 'SKEW' => [1, 1], 'KMERS' => [3, 3], 'FIND' => [2, 2],
  'RESTRICT' => [2, 7], 'PALINDROMES' => [3, 3], 'REPEATS' => [4, 4],
  'HAMMING' => [2, 2], 'ALIGN' => [6, 6], 'CONSENSUS' => [2, 10], 'TM' => [1, 1],
  'MASS' => [1, 1], 'PRIMER' => [1, 1], 'FOLD' => [2, 2], 'ASSEMBLE' => [4, 10],
  'PACK' => [1, 1], 'UNPACK' => [3, 3]
}.freeze
class CommandError < StandardError; end

def revcomp(s)
  s.tr('ACGTRYWSKMBVDHN', 'TGCAYRWSMKVBHDN').reverse
end

def gc(s)
  s.count('GC')
end

def fixed(value, places)
  scale = 10**places
  format("%d.%0#{places}d", value / scale, value % scale)
end

def pct(a, b)
  fixed(10000 * a / b, 2)
end

def transition?(a, b)
  %w[AG GA CT TC].include?(a + b)
end

def frequency_order(table)
  table.keys.sort_by { |item| [-table[item], item] }
end

def codons(s, frame)
  strand = frame.positive? ? s : revcomp(s)
  strand[(frame.abs - 1)..].to_s.scan(/.../)
end

def occurrences(s, motif)
  (0..(s.length - motif.length)).select do |i|
    motif.each_char.with_index.all? { |symbol, j| IUPAC[symbol].include?(s[i + j]) }
  end.map { |i| i + 1 }
end

def repeat_count(s, start, width)
  unit = s[start, width]
  count = 0
  count += 1 while s[start + count * width, width] == unit
  count
end

def primitive?(unit)
  (1...unit.length).none? { |d| (unit.length % d).zero? && unit[0, d] * (unit.length / d) == unit }
end

def longest_palindrome(s)
  best = 0
  (1...s.length).each do |center|
    left = center - 1
    right = center
    while left >= 0 && right < s.length && COMPLEMENT[s[left]] == s[right]
      best = [best, right - left + 1].max
      left -= 1
      right += 1
    end
  end
  best
end

def temperature(s)
  n = s.length
  amount = gc(s)
  n < 14 ? 10 * (2 * (n - amount) + 4 * amount) : (649 * n + 410 * amount - 6724) / n
end

def strand_mass(s)
  s.each_char.sum { |b| BASE_MASS[b] } - (s.length - 1) * 18015
end

class Toolkit
  attr_reader :output

  def initialize
    @registry = {}
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def emit_list(label, values)
    emit(label, *(values.empty? ? ['none'] : values))
  end

  def kinds(cmd, count)
    case cmd
    when 'SEQ' then [:new, :sequence]
    when 'SLICE' then [:name, [1, :n], [1, :n], :new]
    when 'JOIN' then [:new] + Array.new(count - 1, :name)
    when 'MUTATE' then [:name, [1, :n], :base]
    when 'TRANSLATE', 'CODONS', 'PROTEIN' then [:name, [-3, 3, true]]
    when 'ORFS' then [:name, [1, 200]]
    when 'GCWINDOW' then [:name, [1, 500], [1, 500]]
    when 'KMERS' then [:name, [1, 12], [1, 100]]
    when 'FIND' then [:name, :motif]
    when 'RESTRICT' then [:name] + Array.new(count - 1, :enzyme)
    when 'PALINDROMES' then [:name, [2, 20], [2, 20]]
    when 'REPEATS' then [:name, [1, 6], [1, 6], [2, 50]]
    when 'ALIGN' then [:name, :name, :mode, [1, 20], [-20, 0], [-20, -1]]
    when 'FOLD' then [:name, [0, 10]]
    when 'ASSEMBLE' then [:new, [1, 100]] + Array.new(count - 2, :name)
    when 'UNPACK' then [:new, [1, 500], :hex]
    else Array.new(count, :name)
    end
  end

  def validate(cmd, args)
    raise CommandError, "unknown command #{cmd}" unless ARITY.key?(cmd)
    minimum, maximum = ARITY[cmd]
    raise CommandError, 'wrong argument count' unless (minimum..maximum).cover?(args.length)
    values = []
    seen = []
    kinds(cmd, args.length).zip(args).each do |kind, text|
      value = text
      if kind.is_a?(Array)
        upper = kind[1] == :n ? @registry[args[0]].length : kind[1]
        unless /\A-?[0-9]{1,6}\z/.match?(text)
          raise CommandError, "invalid number #{text}"
        end
        value = text.to_i
        if value < kind[0] || value > upper || (kind[2] && value.zero?)
          raise CommandError, "invalid number #{text}"
        end
      elsif kind == :name
        raise CommandError, "unknown sequence #{text}" unless @registry.key?(text)
      elsif kind == :new
        raise CommandError, "invalid name #{text}" unless /\A[a-z][a-z0-9]{0,9}\z/.match?(text)
      elsif kind == :sequence
        text.each_char.with_index do |base, i|
          raise CommandError, "invalid base #{base} at #{i + 1}" unless BASES.include?(base)
        end
      elsif kind == :base
        raise CommandError, "invalid base #{text}" unless text.length == 1 && BASES.include?(text)
      elsif kind == :motif
        unless (1..30).cover?(text.length) && text.each_char.all? { |c| IUPAC.key?(c) }
          raise CommandError, "invalid motif #{text}"
        end
      elsif kind == :enzyme
        raise CommandError, "unknown enzyme #{text}" unless ENZYMES.key?(text)
        raise CommandError, "duplicate enzyme #{text}" if seen.include?(text)
        seen << text
      elsif kind == :mode
        raise CommandError, "invalid mode #{text}" unless %w[GLOBAL LOCAL].include?(text)
      elsif kind == :hex
        unless /\A[0-9A-F]+\z/.match?(text) && text.length == 2 * ((values[1] + 3) / 4)
          raise CommandError, 'invalid hex'
        end
      end
      values << value
    end
    values
  end

  def store(name, s)
    raise CommandError, 'too long' if s.length > 500
    label = @registry.key?(name) ? 'replaced' : 'stored'
    @registry[name] = s
    "#{label} #{name} #{s.length} nt"
  end

  def translation(cmd, s, frame)
    triplets = codons(s, frame)
    protein = triplets.map { |c| CODE[c] }.join
    if cmd == 'TRANSLATE'
      emit(protein.empty? ? 'none' : protein)
    elsif cmd == 'CODONS'
      table = triplets.tally
      frequency_order(table).each { |c| emit(c, CODE[c], table[c]) }
      emit('none') if table.empty?
    else
      protein = protein.partition('*').first
      raise CommandError, 'empty protein' if protein.empty?
      table = protein.chars.tally
      mass = protein.each_char.sum { |a| AMINO_MASS[a] } + 18015
      charge = protein.count('KR') - protein.count('DE')
      emit(protein)
      emit('length', protein.length, 'mass', fixed(mass, 3), 'charge', charge.positive? ? "+#{charge}" : charge)
      emit(*frequency_order(table).map { |a| "#{a}=#{table[a]}" })
    end
  end

  def orfs(s, minimum)
    results = []
    [1, 2, 3, -1, -2, -3].each do |frame|
      triplets = codons(s, frame)
      start = nil
      triplets.each_with_index do |codon, p|
        if start.nil?
          start = p if codon == 'ATG'
        elsif CODE[codon] == '*'
          if p - start >= minimum
            left = frame.abs - 1 + 3 * start
            right = frame.abs - 1 + 3 * (p + 1)
            left, right = s.length - right, s.length - left if frame.negative?
            protein = triplets[start...p].map { |c| CODE[c] }.join
            results << [left + 1, right, frame, protein]
          end
          start = nil
        end
      end
    end
    results.sort_by(&:first).each do |left, right, frame, protein|
      emit(format('%+d', frame), left, right, protein.length, protein)
    end
    emit('none') if results.empty?
  end

  def restrict(s, enzymes)
    combined = []
    enzymes.each do |enzyme|
      motif, offset = ENZYMES[enzyme]
      cuts = occurrences(s, motif).map { |p| p + offset - 1 }.select { |c| c >= 1 && c < s.length }
      emit_list(enzyme, cuts)
      combined.concat(cuts)
    end
    endpoints = [0, *combined.uniq.sort, s.length]
    fragments = endpoints.each_cons(2).map { |a, b| [a + 1, b] }
    emit_list('fragments', fragments.map { |a, b| "#{a}-#{b}" })
    emit_list('sizes', fragments.map { |a, b| b - a + 1 }.sort.reverse)
  end

  def repeats(s, minimum, maximum, limit)
    raise CommandError, 'invalid range' if minimum > maximum
    results = []
    (minimum..maximum).each do |width|
      position = 0
      while position + width <= s.length
        unit = s[position, width]
        count = repeat_count(s, position, width)
        if primitive?(unit) && count >= limit
          results << [position, width, count, unit]
          position += count * width
        else
          position += 1
        end
      end
    end
    results.sort_by { |p, w, _, _| [p, w] }.each do |position, width, count, unit|
      emit("#{position + 1}-#{position + width * count}", "#{unit}x#{count}")
    end
    emit('none') if results.empty?
  end

  def align(a, b, mode, match, mismatch, gap)
    m = a.length
    n = b.length
    local = mode == 'LOCAL'
    table = Array.new(m + 1) { Array.new(n + 1, 0) }
    unless local
      (0..m).each { |i| table[i][0] = i * gap }
      (0..n).each { |j| table[0][j] = j * gap }
    end
    best = 0
    end_i = 0
    end_j = 0
    (1..m).each do |i|
      (1..n).each do |j|
        diagonal = table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch)
        value = [diagonal, table[i - 1][j] + gap, table[i][j - 1] + gap].max
        table[i][j] = local ? [0, value].max : value
        if local && table[i][j] > best
          best = table[i][j]
          end_i = i
          end_j = j
        end
      end
    end
    unless local
      end_i = m
      end_j = n
      best = table[m][n]
    end
    if local && best.zero?
      emit('score', 0)
      return
    end
    i = end_i
    j = end_j
    row_a = []
    row_b = []
    while (local && table[i][j] != 0) || (!local && (i != 0 || j != 0))
      if i.positive? && j.positive? && table[i][j] == table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch)
        row_a << a[i - 1]
        row_b << b[j - 1]
        i -= 1
        j -= 1
      elsif i.positive? && table[i][j] == table[i - 1][j] + gap
        row_a << a[i - 1]
        row_b << '-'
        i -= 1
      else
        row_a << '-'
        row_b << b[j - 1]
        j -= 1
      end
    end
    row_a.reverse!
    row_b.reverse!
    middle = row_a.zip(row_b).map { |x, y| x == '-' || y == '-' ? '-' : x == y ? '|' : '*' }.join
    emit('score', best, 'a', "#{i + 1}-#{end_i}", 'b', "#{j + 1}-#{end_j}",
         'identity', "#{middle.count('|')}/#{middle.length}", 'gaps', middle.count('-'))
    emit(row_a.join)
    emit(middle)
    emit(row_b.join)
  end

  def consensus(sequences)
    n = sequences[0].length
    raise CommandError, 'length mismatch' unless sequences.all? { |s| s.length == n }
    profile = BASES.each_char.to_h { |b| [b, []] }
    consensus = ''
    ambiguous = ''
    n.times do |i|
      table = sequences.map { |s| s[i] }.tally
      largest = table.values.max
      tied = BASES.each_char.select { |b| table[b] == largest }.join
      BASES.each_char { |b| profile[b] << table.fetch(b, 0) }
      consensus += tied[0]
      ambiguous += SYMBOL[tied]
    end
    BASES.each_char { |b| emit(b, *profile[b]) }
    emit('consensus', consensus)
    emit('iupac', ambiguous)
  end

  def primer(s)
    n = s.length
    amount = gc(s)
    tm = temperature(s)
    clamp = gc(s[-5, 5] || s)
    longest_run = s.each_char.chunk(&:itself).map { |_, run| run.length }.max
    repeated = 0
    (0...(n - 1)).each do |i|
      repeated = [repeated, repeat_count(s, i, 2)].max if s[i] != s[i + 1]
    end
    selfcomp = longest_palindrome(s)
    items = [
      ['length', n, (18..25).cover?(n)],
      ['gc', pct(amount, n), 40 * n <= 100 * amount && 100 * amount <= 60 * n],
      ['tm', fixed(tm, 1), (520..620).cover?(tm)],
      ['clamp', clamp, (1..3).cover?(clamp)],
      ['run', longest_run, longest_run <= 4],
      ['repeat', repeated, repeated <= 4],
      ['selfcomp', selfcomp, selfcomp <= 6]
    ]
    failed = []
    items.each do |label, value, passed|
      emit(label, value, passed ? 'OK' : 'FAIL')
      failed << label unless passed
    end
    emit(failed.empty? ? 'PASS' : 'FAIL', *failed)
  end

  def fold(s, loop)
    n = s.length
    raise CommandError, 'too long' if n > 100
    table = Array.new(n) { Array.new(n, 0) }
    value = ->(i, j) { i > j ? 0 : table[i][j] }
    pair = ->(i, j) { %w[AT TA CG GC GT TG].include?(s[i] + s[j]) }
    (2..n).each do |width|
      (0..(n - width)).each do |i|
        j = i + width - 1
        best = value.call(i, j - 1)
        (i...(j - loop)).each do |k|
          best = [best, value.call(i, k - 1) + 1 + value.call(k + 1, j - 1)].max if pair.call(k, j)
        end
        table[i][j] = best
      end
    end
    structure = Array.new(n, '.')
    pending = [[0, n - 1]]
    until pending.empty?
      i, j = pending.pop
      next if value.call(i, j).zero?
      if value.call(i, j) == value.call(i, j - 1)
        pending << [i, j - 1]
        next
      end
      (i...(j - loop)).each do |k|
        next unless pair.call(k, j) && value.call(i, k - 1) + 1 + value.call(k + 1, j - 1) == value.call(i, j)
        structure[k] = '('
        structure[j] = ')'
        pending.push([i, k - 1], [k + 1, j - 1])
        break
      end
    end
    emit(structure.join)
    emit('pairs', table[0][n - 1])
  end

  def assemble(name, minimum, sequences)
    unique = sequences.uniq
    fragments = unique.reject { |s| unique.any? { |t| t != s && t.include?(s) } }
    while fragments.length >= 2
      best = -1
      chosen_i = 0
      chosen_j = 1
      fragments.each_with_index do |x, i|
        fragments.each_with_index do |y, j|
          next if i == j
          overlap = 0
          ([x.length, y.length].min - 1).downto(1) do |width|
            if x[-width, width] == y[0, width]
              overlap = width
              break
            end
          end
          if overlap > best
            best = overlap
            chosen_i = i
            chosen_j = j
          end
        end
      end
      break if best < minimum
      merged = fragments[chosen_i] + fragments[chosen_j][best..]
      fragments = fragments.each_with_index.filter_map do |fragment, i|
        if i == chosen_i
          merged
        elsif i != chosen_j && !merged.include?(fragment)
          fragment
        end
      end
    end
    longest = fragments.max_by(&:length)
    registration = store(name, longest)
    emit('contigs', fragments.length)
    fragments.each { |s| emit(s.length, s) }
    emit(registration)
  end

  def command(cmd, a)
    case cmd
    when 'SEQ'
      emit(store(a[0], a[1]))
      return
    when 'UNPACK'
      codes = []
      a[2].scan(/../).each do |hex|
        value = hex.to_i(16)
        codes.concat([value / 64, value / 16 % 4, value / 4 % 4, value % 4])
      end
      raise CommandError, 'invalid padding' if codes.drop(a[1]).any? { |c| c != 0 }
      emit(store(a[0], codes.first(a[1]).map { |c| BASES[c] }.join))
      return
    when 'JOIN'
      emit(store(a[0], a.drop(1).map { |name| @registry[name] }.join))
      return
    when 'ASSEMBLE'
      assemble(a[0], a[1], a.drop(2).map { |name| @registry[name] })
      return
    when 'LIST'
      @registry.keys.sort.each { |name| emit(name, @registry[name].length, 'nt') }
      emit('no sequences') if @registry.empty?
      return
    end
    name = a[0]
    s = @registry[name]
    n = s.length
    case cmd
    when 'SLICE'
      start, finish = a[1, 2]
      part = start <= finish ? s[(start - 1)...finish] : revcomp(s[(finish - 1)...start])
      emit(store(a[3], part))
    when 'MUTATE'
      position, base = a[1, 2]
      old = s[position - 1]
      raise CommandError, 'no change' if old == base
      @registry[name] = s[0, position - 1] + base + s[position..]
      emit(name, "#{old}#{position}#{base}", transition?(old, base) ? 'transition' : 'transversion')
    when 'DEL'
      @registry.delete(name)
      emit('deleted', name)
    when 'REVCOMP'
      emit(revcomp(s))
    when 'COMPLEMENT'
      emit(s.tr('ACGT', 'TGCA'))
    when 'REVERSE'
      emit(s.reverse)
    when 'TRANSCRIBE'
      emit(s.tr('T', 'U'))
    when 'TRANSLATE', 'CODONS', 'PROTEIN'
      translation(cmd, s, a[1])
    when 'ORFS'
      orfs(s, a[1])
    when 'GC'
      table = s.chars.tally
      emit(*BASES.each_char.map { |b| "#{b}=#{table.fetch(b, 0)}" }, "GC=#{pct(gc(s), n)}%")
    when 'GCWINDOW'
      width, step = a[1, 2]
      raise CommandError, 'window too large' if width > n
      0.step(n - width, step) { |i| emit("#{i + 1}-#{i + width}", pct(gc(s[i, width]), width) + '%') }
    when 'SKEW'
      values = [0]
      s.each_char { |b| values << values.last + (b == 'G' ? 1 : 0) - (b == 'C' ? 1 : 0) }
      [['min', values.min], ['max', values.max]].each do |label, extreme|
        emit(label, extreme, 'at', *values.each_index.select { |i| values[i] == extreme })
      end
    when 'KMERS'
      width, limit = a[1, 2]
      raise CommandError, 'k too large' if width > n
      table = (0..(n - width)).map { |i| s[i, width] }.tally
      emit(n - width + 1, 'windows', table.length, 'distinct')
      frequency_order(table).first(limit).each { |word| emit(word, table[word]) }
    when 'FIND'
      emit_list('forward', occurrences(s, a[1]))
      emit_list('reverse', occurrences(s, revcomp(a[1])))
    when 'RESTRICT'
      restrict(s, a.drop(1))
    when 'PALINDROMES'
      minimum, maximum = a[1, 2]
      raise CommandError, 'invalid range' if minimum > maximum
      found = false
      n.times do |i|
        (minimum..[maximum, n - i].min).each do |width|
          part = s[i, width]
          next unless part == revcomp(part)
          emit(i + 1, width, part)
          found = true
        end
      end
      emit('none') unless found
    when 'REPEATS'
      repeats(s, *a.drop(1))
    when 'HAMMING'
      other = @registry[a[1]]
      raise CommandError, 'length mismatch' unless other.length == n
      distance = s.chars.zip(other.chars).count { |x, y| x != y }
      transitions = s.chars.zip(other.chars).count { |x, y| transition?(x, y) }
      emit('distance', distance, 'transitions', transitions, 'transversions', distance - transitions)
    when 'ALIGN'
      align(s, @registry[a[1]], *a.drop(2))
    when 'CONSENSUS'
      consensus(a.map { |id| @registry[id] })
    when 'TM'
      emit('Tm', fixed(temperature(s), 1), n < 14 ? 'wallace' : 'gc')
    when 'MASS'
      single = strand_mass(s)
      emit('ss', fixed(single, 3), 'ds', fixed(single + strand_mass(revcomp(s)), 3))
    when 'PRIMER'
      primer(s)
    when 'FOLD'
      fold(s, a[1])
    when 'PACK'
      codes = s.each_char.map { |b| BASES.index(b) }
      codes << 0 until (codes.length % 4).zero?
      encoded = codes.each_slice(4).map { |c| format('%02X', 64 * c[0] + 16 * c[1] + 4 * c[2] + c[3]) }.join
      emit(n, encoded)
    end
  end

  def execute(line)
    cmd, *args = line.split(' ')
    begin
      values = validate(cmd, args)
      command(cmd, values)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

toolkit = Toolkit.new
STDIN.gets.to_i.times { toolkit.execute(STDIN.gets.chomp) }
STDOUT.write(toolkit.output.join("\n") + "\n")
