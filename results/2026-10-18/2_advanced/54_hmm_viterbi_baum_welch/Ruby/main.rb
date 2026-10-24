require_relative 'model_io'
require_relative 'inference'
require_relative 'training'
require_relative 'evaluation'
require_relative 'sampler'

module HMM
  Record = Struct.new(:name, :observations, :path)

  def interpret_parameters(rows, model)
    raw = rows.to_h { |row| [row[0], row.drop(1)] }
    integers = %w[iterations folds min_sequence_length max_missing_percent merge_gap min_segment_length min_rich_percent min_motif_percent boundary_tolerance posterior_seed posterior_samples sample_seed sample_count sample_length]
    p = integers.to_h { |key| [key.to_sym, raw[key][0].to_i] }
    %w[pseudocount confidence].each { |key| p[key.to_sym] = raw[key][0].to_f }
    p[:smoothing] = raw['smoothing'].map { |text| [text, text.to_f] }
    p[:segment_state] = model.states.index(raw['segment_state'][0])
    p[:motif] = raw['motif'].map { |symbol| model.symbols.index(symbol) }
    p[:rich_symbols] = raw['rich_symbols'].map { |symbol| model.symbols.index(symbol) }
    p
  end

  def rejection_reason(name, observations, labels, seen, model, p)
    return 'duplicate name' if seen[name]
    seen[name] = true
    observations.each_char.with_index do |c, t|
      return "invalid symbol #{c} at position #{t + 1}" unless model.symbols.include?(c) || c == model.missing
    end
    if labels
      labels.each_char.with_index do |c, t|
        return "invalid label #{c} at position #{t + 1}" unless model.states.include?(c)
      end
      return "length mismatch #{observations.length} #{labels.length}" unless observations.length == labels.length
    end
    return "too short #{observations.length}" if observations.length < p[:min_sequence_length]
    missing = observations.count(model.missing)
    return "too many missing #{missing}" if 100 * missing > p[:max_missing_percent] * observations.length
    nil
  end

  def encode_observations(text, model)
    text.chars.map { |c| c == model.missing ? -1 : model.symbols.index(c) }
  end

  def validate_inputs(sequence_rows, labeled_rows, model, p)
    sequences, training, testing, rejections, seen = [], [], [], [], {}
    sequence_rows.each_with_index do |(name, text), i|
      text = text.upcase
      reason = rejection_reason(name, text, nil, seen, model, p)
      if reason
        rejections << "REJECT sequences.txt line #{i + 1} #{name} #{reason}"
      else
        sequences << Record.new(name, encode_observations(text, model))
      end
    end
    seen = {}
    labeled_rows.each_slice(2).with_index do |(header, label_row), i|
      name, role, text = header
      text, labels = text.upcase, label_row[0]
      reason = rejection_reason(name, text, labels, seen, model, p)
      if reason
        rejections << "REJECT labeled.txt line #{2 * i + 1} #{name} #{reason}"
      else
        record = Record.new(name, encode_observations(text, model), labels.chars.map { |c| model.states.index(c) })
        (role == 'TRAIN' ? training : testing) << record
      end
    end
    [sequences, training, testing, rejections]
  end

  def maximum_change(previous, current)
    old = [previous.initial] + previous.transition + previous.emission
    new_rows = [current.initial] + current.transition + current.emission
    difference = 0.0
    old.zip(new_rows).each { |a, b| a.zip(b).each { |x, y| difference = [difference, (y - x).abs].max } }
    difference
  end

  def train_baum_welch(initial, observations, heldout, p)
    current = initial
    previous = initial_loglik = total_loglik(current, observations)
    best_heldout = total_loglik(current, heldout)
    best_iteration = violations = 0
    trace = ['iteration,loglik,heldout,change,max_change,status', "0,#{real(previous)},#{real(best_heldout)},,,"]
    1.upto(p[:iterations]) do |n|
      updated = baum_welch_step(current, observations, p[:pseudocount])
      likelihood, held = total_loglik(updated, observations), total_loglik(updated, heldout)
      violation = likelihood < previous - 0.000001 * previous.abs
      violations += 1 if violation
      if held > best_heldout
        best_heldout, best_iteration = held, n
      end
      trace << "#{n},#{real(likelihood)},#{real(held)},#{real(likelihood - previous)},#{real(maximum_change(current, updated), 6)},#{violation ? 'violation' : 'ok'}"
      current, previous = updated, likelihood
    end
    [current, trace, {iterations: p[:iterations], initial_loglik: initial_loglik, final_loglik: previous,
                      violations: violations, best_heldout_iteration: best_iteration}]
  end

  def viterbi_paths(model, observations)
    total, paths = 0.0, []
    observations.each do |sequence|
      path, probability = viterbi(model, sequence)
      paths << path
      total += probability
    end
    [paths, total]
  end

  def train_viterbi(initial, observations, p)
    current = initial
    paths, probability = viterbi_paths(current, observations)
    trace = ['iteration,logprob,loglik,changed', "0,#{real(probability)},#{real(total_loglik(current, observations))},"]
    iteration = changed = 0
    1.upto(p[:iterations]) do |n|
      iteration = n
      current = estimate_by_counting(initial, observations.zip(paths), p[:pseudocount], 'VITERBI_TRAINING')
      updated, probability = viterbi_paths(current, observations)
      changed = ordered_sum(paths.zip(updated).map { |a, b| a.length - correct_count(a, b) })
      trace << "#{n},#{real(probability)},#{real(total_loglik(current, observations))},#{changed}"
      paths = updated
      break if changed.zero?
    end
    [current, trace, {iterations: iteration, converged: changed.zero?}]
  end

  def record_pairs(records)
    records.map { |record| [record.observations, record.path] }
  end

  def cross_validate(initial, records, p)
    folds = p[:folds]
    positions = ordered_sum(records.map { |r| r.observations.length })
    results = p[:smoothing].map do |candidate, alpha|
      matrix = confusion_matrix(initial.states.length)
      fold_results = []
      total = 0
      folds.times do |f|
        fitting, validating = [], []
        records.each_with_index { |record, i| (i % folds == f ? validating : fitting) << record }
        model = estimate_by_counting(initial, record_pairs(fitting), alpha)
        count = correct = 0
        validating.each do |record|
          path, = viterbi(model, record.observations)
          count += path.length
          correct += correct_count(record.path, path)
          accumulate_confusion(matrix, record.path, path)
        end
        total += correct
        fold_results << [validating.length, count, correct]
      end
      {candidate: candidate, alpha: alpha, correct: total, folds: fold_results, matrix: matrix}
    end
    selected = results[maximum_index(results.map { |r| r[:correct] })]
    lines = ["CROSS_VALIDATION folds #{folds}"]
    results.each { |r| lines << "SMOOTHING #{r[:candidate]} positions #{positions} correct #{r[:correct]} accuracy #{fraction(r[:correct], positions)}" }
    lines << "SELECTED #{selected[:candidate]}"
    selected[:folds].each_with_index do |(count, n, correct), f|
      lines << "FOLD #{f + 1} records #{count} positions #{n} correct #{correct} accuracy #{fraction(correct, n)}"
    end
    lines.concat(matrix_lines(initial.states, selected[:matrix])).concat(metric_lines(initial.states, selected[:matrix]))
    [estimate_by_counting(initial, record_pairs(records), selected[:alpha]), selected, lines]
  end

  def learning_curve(initial, training, testing, alpha)
    positions = ordered_sum(testing.map { |r| r.observations.length })
    lines = ['LEARNING_CURVE']
    1.upto(training.length) do |n|
      model = estimate_by_counting(initial, record_pairs(training.first(n)), alpha)
      correct = 0
      testing.each { |r| correct += correct_count(r.path, viterbi(model, r.observations)[0]) }
      lines << "RECORDS #{n} correct #{correct} accuracy #{fraction(correct, positions)}"
    end
    lines
  end

  def extract_segments(path, p)
    segments = []
    runs(path).each do |state, start, finish|
      next unless state == p[:segment_state]
      if !segments.empty? && start - segments[-1][1] - 1 <= p[:merge_gap]
        segments[-1][1] = finish
      else
        segments << [start, finish]
      end
    end
    segments.select { |start, finish| finish - start + 1 >= p[:min_segment_length] }
  end

  def composition(observations, segment, p)
    start, finish = segment
    first, second = p[:motif]
    n = rich = k1 = k2 = pairs = 0
    (start - 1...finish).each do |t|
      c = observations[t]
      unless c == -1
        n += 1
        rich += 1 if p[:rich_symbols].include?(c)
        k1 += 1 if c == first
        k2 += 1 if c == second
      end
      pairs += 1 if t + 1 < finish && c == first && observations[t + 1] == second
    end
    denominator = k1 * k2
    [n.zero? ? nil : rich.to_f / n, denominator.zero? ? nil : (pairs * n).to_f / denominator,
     denominator > 0 && 100 * rich >= p[:min_rich_percent] * n && 100 * pairs * n >= p[:min_motif_percent] * k1 * k2]
  end

  def evaluate_model(model, records, p)
    decoded = records.map { |r| decode(model, r.observations) }
    blocks, totals = [], []
    %w[VITERBI POSTERIOR].each do |decoder|
      matrix = confusion_matrix(model.states.length)
      regions, bounds = Array.new(4, 0), Array.new(4, 0)
      calibration = Array.new(10) { [0, 0] }
      record_lines, total = [], 0
      records.zip(decoded).each do |record, result|
        path = decoder == 'VITERBI' ? result.viterbi : result.posterior
        correct = correct_count(record.path, path)
        total += correct
        accumulate_confusion(matrix, record.path, path)
        truth = runs(record.path).select { |state, _, _| state == p[:segment_state] }.map { |_, s, e| [s, e] }
        rc = region_counts(extract_segments(path, p), truth)
        bc = boundary_counts(path, record.path, p[:boundary_tolerance])
        4.times { |i| regions[i] += rc[i]; bounds[i] += bc[i] }
        if decoder == 'POSTERIOR'
          result.confidence.each_with_index do |confidence, t|
            b = [(10 * confidence).floor, 9].min
            calibration[b][0] += 1
            calibration[b][1] += 1 if path[t] == record.path[t]
          end
        end
        record_lines << "RECORD #{record.name} length #{path.length} correct #{correct}"
      end
      lines = ["EVALUATION #{model.name} #{decoder}"] + matrix_lines(model.states, matrix) + metric_lines(model.states, matrix)
      lines << "REGIONS #{model.states[p[:segment_state]]} predicted #{regions[0]} true #{regions[1]} precision #{fraction(regions[2], regions[0])} recall #{fraction(regions[3], regions[1])}"
      lines << "BOUNDARIES predicted #{bounds[0]} true #{bounds[1]} precision #{fraction(bounds[2], bounds[0])} recall #{fraction(bounds[3], bounds[1])}"
      if decoder == 'POSTERIOR'
        calibration.each_with_index do |(n, correct), b|
          next if n.zero?
          interval = b < 9 ? "0.#{b}-0.#{b + 1}" : '0.9-1.0'
          lines << "CALIBRATION #{interval} positions #{n} correct #{correct} accuracy #{fraction(correct, n)}"
        end
      end
      blocks << lines + record_lines
      totals << total
    end
    [blocks, totals]
  end

  def state_string(model, path)
    path.map { |i| model.states[i] }.join
  end

  def imputed_string(model, observations, posterior)
    observations.each_with_index.map do |c, t|
      if c == -1
        probabilities = Array.new(model.symbols.length) do |symbol|
          total = 0.0
          model.states.length.times { |i| total += posterior[t][i] * model.emission[i][symbol] }
          total
        end
        model.symbols[maximum_index(probabilities)].downcase
      else
        model.symbols[c]
      end
    end.join
  end

  def segment_line(record, decoder, segment, result, samples, p)
    start, finish = segment
    length, state = finish - start + 1, p[:segment_state]
    total = 0.0
    (start - 1...finish).each { |t| total += result.fb.posterior[t][state] }
    support = samples.count { |path| 2 * path[start - 1, length].count(state) > length }
    rich, ratio, island = composition(record.observations, segment, p)
    [record.name, decoder, start, finish, length, real(total / length), support, real(rich), real(ratio), island ? 'yes' : 'no'].join(',')
  end

  def annotate_sequences(model, records, decoded, p)
    generator = MINSTD.new(p[:posterior_seed])
    lines = []
    segments = ['sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island']
    records.zip(decoded).each do |record, result|
      samples = Array.new(p[:posterior_samples]) { posterior_path(model, result.fb.forward, generator) }
      expected = ordered_sum(samples.map { |path| extract_segments(path, p).length }).to_f / p[:posterior_samples]
      length = record.observations.length
      differences = length - correct_count(result.viterbi, result.posterior)
      uncertain = result.confidence.count { |c| c < p[:confidence] }
      confident = result.posterior.each_with_index.map { |i, t| result.confidence[t] < p[:confidence] ? '.' : model.states[i] }.join
      lines.concat(["SEQUENCE #{record.name} length #{length} loglik #{real(result.fb.loglik)} viterbi #{real(result.viterbi_logprob)} differences #{differences} uncertain #{uncertain} expected_segments #{real(expected)}",
                    'VITERBI ' + state_string(model, result.viterbi), 'POSTERIOR ' + state_string(model, result.posterior),
                    'CONFIDENT ' + confident, 'IMPUTED ' + imputed_string(model, record.observations, result.fb.posterior)])
      [['viterbi', result.viterbi], ['posterior', result.posterior]].each do |decoder, path|
        extract_segments(path, p).each { |segment| segments << segment_line(record, decoder, segment, result, samples, p) }
      end
    end
    [lines, segments]
  end

  def synthetic_output(model, p)
    generator = MINSTD.new(p[:sample_seed])
    lines, vtotal, ptotal, positions = [], 0, 0, 0
    1.upto(p[:sample_count]) do |n|
      truth, observations = synthetic_sequence(model, p[:sample_length], generator)
      result = decode(model, observations)
      vc, pc = correct_count(truth, result.viterbi), correct_count(truth, result.posterior)
      vtotal += vc
      ptotal += pc
      positions += truth.length
      lines.concat(["SAMPLE #{n} loglik #{real(result.fb.loglik)} viterbi #{real(result.viterbi_logprob)} viterbi_correct #{vc} posterior_correct #{pc}",
                    'STATES ' + state_string(model, truth), 'SYMBOLS ' + observations.map { |c| model.symbols[c] }.join,
                    'VITERBI ' + state_string(model, result.viterbi), 'POSTERIOR ' + state_string(model, result.posterior)])
    end
    lines << "TOTAL positions #{positions} viterbi_accuracy #{fraction(vtotal, positions)} posterior_accuracy #{fraction(ptotal, positions)}"
  end

  def path_statistics(paths, k)
    counts, run_counts, total = Array.new(k, 0), Array.new(k, 0), 0
    paths.each do |path|
      total += path.length
      runs(path).each { |i, s, e| counts[i] += e - s + 1; run_counts[i] += 1 }
    end
    [counts, run_counts, total]
  end

  def stationary_distribution(model)
    k = model.states.length
    matrix = Array.new(k - 1) { |j| Array.new(k) { |i| model.transition[i][j] - (i == j ? 1.0 : 0.0) } + [0.0] }
    matrix << Array.new(k + 1, 1.0)
    k.times do |column|
      pivot = (column...k).max_by { |r| matrix[r][column].abs }
      matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
      divisor = matrix[column][column]
      (column..k).each { |j| matrix[column][j] /= divisor }
      k.times do |row|
        next if row == column
        factor = matrix[row][column]
        (column..k).each { |j| matrix[row][j] -= factor * matrix[column][j] }
      end
    end
    matrix.map { |row| row[k] }
  end

  def state_alignment(model, records)
    k = model.states.length
    matrix, positions = confusion_matrix(k), 0
    records.each do |r|
      path, = viterbi(model, r.observations)
      accumulate_confusion(matrix, r.path, path)
      positions += path.length
    end
    best_correct, best = -1, nil
    (0...k).to_a.permutation.each do |permutation|
      correct = ordered_sum(permutation.each_with_index.map { |actual, predicted| matrix[actual][predicted] })
      best_correct, best = correct, permutation if correct > best_correct
    end
    mapping = best.each_with_index.map { |actual, i| "#{model.states[i]}=#{model.states[actual]}" }.join(' ')
    "ALIGNMENT #{mapping} agreement #{fraction(best_correct, positions)}"
  end

  def model_diagnostics(model, records, decoded, training, testing, p)
    likelihood, observed, count, length, islands = 0.0, 0, 0, 0, 0
    records.zip(decoded).each do |record, result|
      likelihood += result.fb.loglik
      observed += record.observations.count { |c| c != -1 }
      extract_segments(result.viterbi, p).each do |segment|
        count += 1
        length += segment[1] - segment[0] + 1
        islands += 1 if composition(record.observations, segment, p)[2]
      end
    end
    counts, run_counts, total = path_statistics(decoded.map(&:viterbi), model.states.length)
    stationary = stationary_distribution(model)
    lines = ["MODEL #{model.name}", "LOGLIK unlabeled #{real(likelihood)} per_symbol #{real(likelihood / observed)} test #{real(total_loglik(model, testing.map(&:observations)))}",
             "SEGMENTS count #{count} mean_length #{real(count.zero? ? nil : length.to_f / count)} islands #{islands}", state_alignment(model, training)]
    model.states.each_with_index do |state, i|
      lines << "STATE #{state} stationary #{real(stationary[i])} duration #{real(1.0 / (1.0 - model.transition[i][i]))} occupancy #{real(counts[i].to_f / total)} mean_run #{real(run_counts[i].zero? ? nil : counts[i].to_f / run_counts[i])}"
    end
    lines
  end

  def input_report(model, sequences, training, testing, rejections, sequence_count, labeled_count)
    positions = ordered_sum(sequences.map { |r| r.observations.length })
    missing = ordered_sum(sequences.map { |r| r.observations.count(-1) })
    labeled = training + testing
    lines = ['INPUT', "SEQUENCES accepted #{sequences.length} rejected #{sequence_count - sequences.length} positions #{positions} missing #{missing}",
             "LABELED train #{training.length} test #{testing.length} rejected #{labeled_count - labeled.length} positions #{ordered_sum(labeled.map { |r| r.observations.length })} missing #{ordered_sum(labeled.map { |r| r.observations.count(-1) })}"] + rejections
    symbols = Array.new(model.symbols.length, 0)
    sequences.each { |r| r.observations.each { |c| symbols[c] += 1 unless c == -1 } }
    lines << 'COMPOSITION ' + model.symbols.each_with_index.map { |c, i| "#{c} #{real(symbols[i].to_f / (positions - missing))}" }.join(' ')
    [['TRAIN', training], ['TEST', testing]].each do |role, records|
      counts, run_counts, total = path_statistics(records.map(&:path), model.states.length)
      model.states.each_with_index do |state, i|
        lines << "TRUTH #{role} #{state} occupancy #{real(counts[i].to_f / total)} mean_run #{real(run_counts[i].zero? ? nil : counts[i].to_f / run_counts[i])}"
      end
    end
    lines
  end

  def training_report(models, bw, vt, selected, decoded, scores, test_positions)
    lines = ["TRAINING BAUM_WELCH iterations #{bw[:iterations]} initial_loglik #{real(bw[:initial_loglik])} final_loglik #{real(bw[:final_loglik])} violations #{bw[:violations]} best_heldout_iteration #{bw[:best_heldout_iteration]}",
             "TRAINING VITERBI_TRAINING iterations #{vt[:iterations]} converged #{vt[:converged] ? 'yes' : 'no'}", "TRAINING SUPERVISED smoothing #{selected[:candidate]}"]
    preferences = Array.new(models.length, 0)
    decoded[0].length.times { |n| preferences[maximum_index(decoded.map { |results| results[n].fb.loglik })] += 1 }
    lines << 'PREFERENCE ' + models.each_with_index.map { |model, i| "#{model.name} #{preferences[i]}" }.join(' ')
    positions = ordered_sum(decoded[0].map { |r| r.viterbi.length })
    models.length.times do |i|
      (i + 1...models.length).each do |j|
        correct = ordered_sum(decoded[i].zip(decoded[j]).map { |a, b| correct_count(a.viterbi, b.viterbi) })
        lines << "AGREEMENT #{models[i].name} #{models[j].name} #{fraction(correct, positions)}"
      end
    end
    %w[VITERBI POSTERIOR].each_with_index do |decoder, i|
      best = maximum_index(scores.map { |score| score[i] })
      lines << "BEST #{decoder} #{models[best].name} accuracy #{fraction(scores[best][i], test_positions)}"
    end
    lines
  end

  def join_blocks(blocks)
    lines = []
    blocks.each do |block|
      lines << '' unless lines.empty?
      lines.concat(block)
    end
    lines
  end

  def main
    initial, sequence_rows, labeled_rows, parameter_rows = read_inputs
    p = interpret_parameters(parameter_rows, initial)
    sequences, training, testing, rejections = validate_inputs(sequence_rows, labeled_rows, initial, p)
    observations, heldout = sequences.map(&:observations), (training + testing).map(&:observations)
    bw, bw_trace, bw_summary = train_baum_welch(initial, observations, heldout, p)
    vt, vt_trace, vt_summary = train_viterbi(initial, observations, p)
    supervised, selected, cv = cross_validate(initial, training, p)
    learning = learning_curve(initial, training, testing, selected[:alpha])
    models = [initial, bw, vt, supervised]
    evaluation_blocks, scores = [], []
    models.each do |model|
      blocks, totals = evaluate_model(model, testing, p)
      evaluation_blocks.concat(blocks)
      scores << totals
    end
    evaluation_blocks.concat([cv, learning])
    decoded = models.map { |model| sequences.map { |r| decode(model, r.observations) } }
    decodings, segments = annotate_sequences(bw, sequences, decoded[1], p)
    report = [input_report(initial, sequences, training, testing, rejections, sequence_rows.length, labeled_rows.length / 2),
              training_report(models, bw_summary, vt_summary, selected, decoded, scores, ordered_sum(testing.map { |r| r.observations.length }))]
    models.zip(decoded).each { |model, results| report << model_diagnostics(model, sequences, results, training, testing, p) }
    outputs = {'trained_model.txt' => join_blocks(models.drop(1).map { |model| model_lines(model) }),
               'loglik_trace.csv' => bw_trace, 'viterbi_trace.csv' => vt_trace, 'decodings.txt' => decodings,
               'segments.csv' => segments, 'samples.txt' => synthetic_output(bw, p),
               'evaluation.txt' => join_blocks(evaluation_blocks), 'report.txt' => join_blocks(report)}
    outputs.each { |filename, lines| write_lines(filename, lines) }
  end
end

HMM.main if $PROGRAM_NAME == __FILE__
