require_relative 'dataset'
require_relative 'multiclass'
include Evaluation

def support_counts(model)
  total = model.alpha.count { |a| a > 0 }
  bound = model.alpha.count { |a| a > 0 && a == model.c }
  [total, bound, total - bound]
end

def support_text(model)
  total, bound, free = support_counts(model)
  "support_vectors #{total} bound #{bound} free #{free}"
end

def run_info(m) = "passes #{m.passes} steps #{m.steps} converged #{m.converged ? 'yes' : 'no'}"

def objectives(model, alpha = model.alpha)
  scores = model.matrix.map do |row|
    total = 0.0
    alpha.each_with_index { |a, i| total += a * model.labels[i] * row[i] if a > 0 }
    total
  end
  q = total = 0.0
  alpha.each_with_index do |a, i|
    q += a * model.labels[i] * scores[i]
    total += a
  end
  [q, total - q / 2.0]
end

def cross_validate(training, s)
  points, labels = training.map(&:point), training.map(&:label)
  matrices, combinations, best = [], [], []
  partitions = folds(training.size, s.folds)
  s.kernels.each_with_index do |kernel, ki|
    matrix = kernel.matrix(points)
    matrices << matrix
    candidates = s.c_grid.map do |c|
      values = Array.new(training.size, 0.0)
      results = partitions.map do |tr, te|
        model = train(tr.map { |i| points[i] }, tr.map { |i| labels[i] }, kernel, submatrix(matrix, tr), c, s)
        correct = 0
        te.each do |i|
          values[i] = model.decision(points[i])
          correct += 1 if sign(values[i]) == labels[i]
        end
        { train: tr.size, test: te.size, correct: correct, support: support_counts(model)[0], model: model }
      end
      r = { kernel: kernel, ki: ki, c: c, values: values, folds: results,
            correct: results.sum { |f| f[:correct] }, support: results.sum { |f| f[:support] },
            passes: results.sum { |f| f[:model].passes }, steps: results.sum { |f| f[:model].steps } }
      combinations << r
      r
    end
    best << candidates.min_by { |r| [-r[:correct], r[:c]] }
  end
  ranking = combinations.sort_by { |r| [-r[:correct], r[:c], r[:ki]] }
  [matrices, combinations, best, best.min_by { |r| [-r[:correct], r[:c], r[:ki]] }, ranking]
end

def cv_lines(n, k, best, selected, ranking)
  lines = ["cross_validation folds #{k} examples #{n}"]
  best.each { |r| lines << "best #{r[:kernel].name} C #{fixed(r[:c])} correct #{r[:correct]}/#{n} accuracy #{ratio(r[:correct], n)}" }
  lines += ["selected #{selected[:kernel].name} C #{fixed(selected[:c])}", 'ranking']
  ranking.each_with_index { |r, i| lines << "#{i + 1} #{r[:kernel].name} C #{fixed(r[:c])} correct #{r[:correct]}/#{n}" }
  lines << "cv_detail #{selected[:kernel].name} C #{fixed(selected[:c])}"
  selected[:folds].each_with_index { |f, i| lines << "fold #{i + 1} train #{f[:train]} test #{f[:test]} correct #{f[:correct]} support_vectors #{f[:support]} #{run_info(f[:model])}" }
  lines
end

def evaluate_final(model, training, testing, tolerance)
  n, m = training.size, testing.size
  tv, ev = model.training_decisions, testing.map { |e| model.decision(e.point) }
  labels = testing.map(&:label)
  q, dual = objectives(model)
  sy = sg = equality = w1 = w2 = 0.0
  model.matrix.each_with_index do |row, i|
    row.each_with_index do |v, j|
      sy += model.labels[i] * model.labels[j] * v
      sg += v * v
    end
  end
  counts = { 1 => { bound: 0, free: 0 }, -1 => { bound: 0, free: 0 } }
  training.zip(model.alpha).each do |e, a|
    equality += a * e.label
    if model.kernel.kind == 'linear'
      w1 += a * e.label * e.point[0]
      w2 += a * e.label * e.point[1]
    end
    counts[e.label][a == model.c ? :bound : :free] += 1 if a > 0
  end
  radius = (0...n).map { |i| model.matrix[i][i] }.max - model.matrix.flatten.min
  hinge = largest = 0.0
  violations = errors = 0
  model.alpha.zip(model.labels, tv).each do |a, y, v|
    h = [0.0, 1 - y * v].max
    hinge += h
    r = y * v - 1
    violation = a.zero? ? [0.0, -r].max : (a == model.c ? [0.0, r].max : r.abs)
    violations += 1 if violation > tolerance
    largest = [largest, violation].max
    errors += 1 if 2 * a * radius + h >= 1
  end
  primal, norm = q / 2.0 + model.c * hinge, Math.sqrt(q)
  tc = correct_count(model.labels, tv)
  tp, fp, tn, fn = binary_counts(labels, ev)
  positive = negative = 0.0
  labels.zip(ev).each { |y, v| y == 1 ? positive += v : negative += v }
  p, neg = counts[1], counts[-1]
  lines = ["model #{model.kernel.name}", "kernel #{model.kernel.description}", "C #{fixed(model.c)}",
           "alignment #{fixed(sy / (n * Math.sqrt(sg)), 6)}",
           "passes #{model.passes} full #{model.full_passes} nonbound #{model.nonbound_passes} converged #{model.converged ? 'yes' : 'no'}",
           "examined #{model.examined} steps #{model.steps}",
           "choice heuristic #{model.choices[:heuristic]} nonbound_loop #{model.choices[:nonbound_loop]} full_loop #{model.choices[:full_loop]}",
           "clipping none #{model.clipping[:none]} lower #{model.clipping[:lower]} upper #{model.clipping[:upper]}",
           support_text(model), "b #{fixed(model.b, 6)}", "equality #{fixed(equality, 6)}"]
  lines << "w #{fixed(w1, 6)} #{fixed(w2, 6)}" if model.kernel.kind == 'linear'
  lines += ["sv_by_class positive bound #{p[:bound]} free #{p[:free]} negative bound #{neg[:bound]} free #{neg[:free]}",
            "norm #{fixed(norm, 6)} margin #{fixed(2.0 / norm, 6)}", "dual_objective #{fixed(dual, 6)}",
            "primal_objective #{fixed(primal, 6)}", "duality_gap #{fixed(primal - dual, 6)}",
            "kkt_violations #{violations} max #{fixed(largest, 6)}",
            "xi_alpha radius #{fixed(radius, 6)} errors #{errors}/#{n} accuracy #{ratio(n - errors, n)}",
            "train correct #{tc}/#{n} accuracy #{ratio(tc, n)}",
            "test correct #{tp + tn}/#{m} accuracy #{ratio(tp + tn, m)} tp #{tp} fp #{fp} tn #{tn} fn #{fn}",
            "test precision #{ratio(tp, tp + fp)} recall #{ratio(tp, tp + fn)} f1 #{ratio(2 * tp, 2 * tp + fp + fn)} auc #{fixed(auc(labels, ev))}",
            "test inside_margin #{ev.count { |v| v.abs < 1 }}",
            "test mean_decision positive #{fixed(positive / (tp + fn))} negative #{fixed(negative / (fp + tn))}"]
  training.zip(model.alpha, tv).each do |e, a, v|
    lines << "sv #{e.id} y #{e.label} alpha #{fixed(a, 6)} f #{fixed(v)} #{a == model.c ? 'bound' : 'free'}" if a > 0
  end
  { model: model, train_values: tv, test_values: ev, weights: [w1, w2], lines: lines }
end

def training_log(model)
  lines, i = ["training_log #{model.kernel.name}"], 0
  while i < model.records.size
    r = model.records[i]
    if r[:full]
      lines << "pass #{i + 1} full examined #{r[:examined]} changed #{r[:changed]} dual_objective #{fixed(objectives(model, r[:alpha])[1], 6)}"
      i += 1
    else
      first, examined, changed = i + 1, 0, 0
      while i < model.records.size && !model.records[i][:full]
        examined += model.records[i][:examined]
        changed += model.records[i][:changed]
        i += 1
      end
      lines << "passes #{first}-#{i} nonbound examined #{examined} changed #{changed}"
    end
  end
  lines
end

def path_and_curve(training, testing, selected, matrix, s)
  kernel, c = selected.values_at(:kernel, :c)
  labels = testing.map(&:label)
  path = ["c_path #{kernel.name}"]
  s.c_grid.each do |value|
    model = train(training.map(&:point), training.map(&:label), kernel, matrix, value, s)
    path << "C #{fixed(value)} #{support_text(model)} dual_objective #{fixed(objectives(model)[1], 6)} train #{correct_count(model.labels, model.training_decisions)}/#{training.size} test #{correct_count(labels, testing.map { |e| model.decision(e.point) })}/#{testing.size} #{run_info(model)}"
  end
  curve = ["learning_curve #{kernel.name} C #{fixed(c)}"]
  s.learning_curve.each do |percentage|
    size = training.size * percentage / 100
    rows = training.first(size)
    model = train(rows.map(&:point), rows.map(&:label), kernel, submatrix(matrix, (0...size).to_a), c, s)
    curve << "size #{size} support_vectors #{support_counts(model)[0]} train #{correct_count(model.labels, model.training_decisions)}/#{size} test #{correct_count(labels, testing.map { |e| model.decision(e.point) })}/#{testing.size} #{run_info(model)}"
  end
  [path, curve]
end

def probability(v, a, b) = 1.0 / (1 + Math.exp(a * v + b))
def nll(values, targets, a, b)
  total = 0.0
  values.zip(targets).each do |v, t|
    p = probability(v, a, b)
    total += t * Math.log(p) + (1 - t) * Math.log(1 - p)
  end
  -total
end

def calibrate(training, testing, selected, test_values, iterations)
  pos = training.count { |e| e.label == 1 }
  neg = training.size - pos
  targets = training.map { |e| e.label == 1 ? (pos + 1).to_f / (pos + 2) : 1.0 / (neg + 2) }
  values, a, b = selected[:values], 0.0, Math.log((neg + 1).to_f / (pos + 1))
  lines = ["calibration #{selected[:kernel].name} C #{fixed(selected[:c])} positives #{pos} negatives #{neg}",
           "start A #{fixed(a, 6)} B #{fixed(b, 6)} nll #{fixed(nll(values, targets, a, b), 6)}"]
  1.upto(iterations) do |iteration|
    g1 = g2 = h11 = h21 = h22 = 0.0
    values.zip(targets).each do |v, target|
      p = probability(v, a, b)
      g1 += v * (target - p)
      g2 += target - p
      h11 += v * v * p * (1 - p)
      h21 += v * p * (1 - p)
      h22 += p * (1 - p)
    end
    det = h11 * h22 - h21 * h21
    a -= (h22 * g1 - h21 * g2) / det
    b -= (h11 * g2 - h21 * g1) / det
    lines << "iteration #{iteration} A #{fixed(a, 6)} B #{fixed(b, 6)} nll #{fixed(nll(values, targets, a, b), 6)}"
  end
  probabilities = test_values.map { |v| probability(v, a, b) }
  log_total = brier = 0.0
  bins = Array.new(5) { { count: 0, total: 0.0, positive: 0 } }
  testing.zip(probabilities).each do |e, p|
    positive = e.label == 1
    log_total += Math.log(positive ? p : 1 - p)
    d = p - (positive ? 1 : 0)
    brier += d * d
    bin = bins[[4, (p * 5).floor].min]
    bin[:count] += 1
    bin[:total] += p
    bin[:positive] += 1 if positive
  end
  lines << "test log_loss #{fixed(-log_total / testing.size, 6)} brier #{fixed(brier / testing.size, 6)}"
  %w[0.0-0.2 0.2-0.4 0.4-0.6 0.6-0.8 0.8-1.0].zip(bins).each do |range, bin|
    count = bin[:count]
    lines << "bin #{range} count #{count} mean_probability #{count > 0 ? fixed(bin[:total] / count) : '-'} positive_rate #{ratio(bin[:positive], count)}"
  end
  testing.each_index.sort_by { |i| [test_values[i].abs, i] }.first(5).each do |i|
    e = testing[i]
    lines << "closest #{e.id} label #{e.label} decision #{fixed(test_values[i])} probability #{fixed(probabilities[i])}"
  end
  [a, b, probabilities, lines]
end

def linear_decision(w, p) = w[0] * p[0] + w[1] * p[1] + w[2]

def pegasos(training, testing, parameters, comparison)
  lambda, iterations, seed = parameters
  state, updates = seed, 0
  w, sums = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
  n, m = training.size, testing.size
  labels, test_labels = training.map(&:label), testing.map(&:label)
  lines = ["pegasos lambda #{fixed(lambda)} iterations #{iterations} seed #{seed}"]
  1.upto(iterations) do |t|
    state = 48_271 * state % 2_147_483_647
    e = training[state % n]
    eta = 1.0 / (lambda * t)
    sigma = 1 - eta * lambda
    if e.label * linear_decision(w, e.point) < 1
      w = [sigma * w[0] + eta * e.label * e.point[0], sigma * w[1] + eta * e.label * e.point[1], sigma * w[2] + eta * e.label]
      updates += 1
    else
      w = w.map { |v| sigma * v }
    end
    3.times { |i| sums[i] += w[i] }
    next unless t % (iterations / 10) == 0
    values = training.map { |row| linear_decision(w, row.point) }
    hinge = 0.0
    labels.zip(values).each { |y, v| hinge += [0.0, 1 - y * v].max }
    objective = lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) + hinge / n
    lines << "checkpoint #{t} objective #{fixed(objective, 6)} train #{correct_count(labels, values)}/#{n}"
  end
  average = sums.map { |v| v / iterations }
  tv, ev = training.map { |e| linear_decision(w, e.point) }, testing.map { |e| linear_decision(w, e.point) }
  tc, ec = correct_count(labels, tv), correct_count(test_labels, ev)
  ac = correct_count(test_labels, testing.map { |e| linear_decision(average, e.point) })
  v1, v2 = comparison[:weights]
  cosine = (w[0] * v1 + w[1] * v2) / (Math.sqrt(w[0] * w[0] + w[1] * w[1]) * Math.sqrt(v1 * v1 + v2 * v2))
  agreement = ev.zip(comparison[:test_values]).count { |a, b| sign(a) == sign(b) }
  lines += ["updates #{updates}", "w #{fixed(w[0], 6)} #{fixed(w[1], 6)} bias #{fixed(w[2], 6)}",
            "train correct #{tc}/#{n} accuracy #{ratio(tc, n)}", "test correct #{ec}/#{m} accuracy #{ratio(ec, m)}",
            "average w #{fixed(average[0], 6)} #{fixed(average[1], 6)} bias #{fixed(average[2], 6)} test correct #{ac}/#{m}",
            "compare #{comparison[:model].kernel.name} cosine #{fixed(cosine, 6)} test_agreement #{agreement}/#{m}"]
  [ev, lines]
end

def mcnemar_lines(testing, results, pegasos_values)
  names = results.map { |r| r[:model].kernel.name } + ['pegasos']
  correct = (results.map { |r| r[:test_values] } + [pegasos_values]).map { |values| testing.zip(values).map { |e, v| sign(v) == e.label } }
  lines = ['mcnemar']
  names.each_index do |a|
    (a + 1...names.size).each do |b|
      n1 = n2 = 0
      correct[a].zip(correct[b]).each do |x, y|
        n1 += 1 if x && !y
        n2 += 1 if y && !x
      end
      d = (n1 - n2).abs - 1
      lines << "#{names[a]} #{names[b]} only_first #{n1} only_second #{n2} chi2 #{n1 + n2 > 0 ? fixed((d * d).to_f / (n1 + n2)) : '-'}"
    end
  end
  lines
end

def multiclass_lines(training, testing, multi)
  tr, te = [training, testing].map { |rows| rows.map { |e| multi.classify(e.point) } }
  lines = ["multiclass kernel #{multi.kernel.name} C #{fixed(multi.c)} classes 3 train #{training.size} test #{testing.size}", 'ovr']
  multi.ovr_models.each_with_index do |model, i|
    correct = testing.zip(te).count { |e, r| sign(r.ovr_values[i]) == (e.class_number == i + 1 ? 1 : -1) }
    lines << "model #{i + 1}-rest examples #{training.size} positives #{model.labels.count(1)} #{support_text(model)} b #{fixed(model.b, 6)} #{run_info(model)} test #{correct}/#{testing.size}"
  end
  lines << 'ovo'
  multi.ovo_models.each_with_index do |model, i|
    a, b = PAIRS[i]
    rows = testing.zip(te).select { |e, _| [a, b].include?(e.class_number) }
    correct = rows.count { |e, r| sign(r.ovo_values[i]) == (e.class_number == a ? 1 : -1) }
    lines << "model #{a}-#{b} examples #{model.points.size} positives #{model.labels.count(1)} #{support_text(model)} b #{fixed(model.b, 6)} #{run_info(model)} test #{correct}/#{rows.size}"
  end
  lines << 'predictions'
  testing.zip(te).each do |e, r|
    lines << "#{e.id} class #{e.class_number} ovr #{r.ovr_values.map { |v| fixed(v) }.join(' ')} pred #{r.ovr} ovo #{r.ovo_values.map { |v| fixed(v) }.join(' ')} votes #{r.votes.join(' ')} pred #{r.ovo}"
  end
  [['train', training, tr], ['test', testing, te]].each do |role, rows, results|
    rc = rows.zip(results).count { |e, r| e.class_number == r.ovr }
    pc = rows.zip(results).count { |e, r| e.class_number == r.ovo }
    lines << "#{role} ovr #{rc}/#{rows.size} #{ratio(rc, rows.size)} ovo #{pc}/#{rows.size} #{ratio(pc, rows.size)} agreement #{results.count { |r| r.ovr == r.ovo }}/#{rows.size} vote_ties #{results.count(&:tied)}"
  end
  [:ovr, :ovo].each do |method|
    lines << "confusion #{method}"
    lines.concat(confusion_lines(confusion_matrix(testing.map(&:class_number), te.map(&method))))
  end
  lines
end

def framed_plot(cells, w)
  border = '+' + '-' * w + '+'
  [border] + cells.each_slice(w).map { |row| '|' + row.join + '|' } + [border]
end

def plot_cell(point, xmin, ymax, dx, dy, w, h)
  c, r = ((point[0] - xmin) / dx).floor, ((ymax - point[1]) / dy).floor
  r * w + c if c >= 0 && c < w && r >= 0 && r < h
end

def decision_plots(training, multi_training, results, selected, a, b, multi, s)
  w, h = s.plot_size
  xmin, xmax = s.plot_x
  ymin, ymax = s.plot_y
  dx, dy = (xmax - xmin) / w, (ymax - ymin) / h
  model = results[selected[:ki]][:model]
  binary, probs, multicells = [], [], []
  signs, levels = results.map { [] }, Array.new(10, 0)
  h.times do |r|
    w.times do |c|
      point = [xmin + (c + 0.5) * dx, ymax - (r + 0.5) * dy]
      values = results.map { |result| result[:model].decision(point) }
      v = values[selected[:ki]]
      binary << (v >= 1 ? '+' : (v > 0 ? '.' : (v > -1 ? '-' : ' ')))
      level = [9, (probability(v, a, b) * 10).floor].min
      probs << level.to_s
      levels[level] += 1
      signs.zip(values).each { |array, value| array << sign(value) }
      result = multi.classify(point)
      multicells << (result.ovr != result.ovo ? '?' : [' ', '.', ':'][result.ovr - 1])
    end
  end
  assignments, outside = Array.new(w * h), 0
  training.each_with_index do |e, i|
    cell = plot_cell(e.point, xmin, ymax, dx, dy, w, h)
    if cell.nil?
      outside += 1
    else
      previous = assignments[cell]
      assignments[cell] = i if previous.nil? || (model.alpha[i] > 0 && model.alpha[previous] <= 0)
    end
  end
  assignments.each_with_index do |i, cell|
    next if i.nil?
    binary[cell] = training[i].label == 1 ? (model.alpha[i] > 0 ? 'X' : 'x') : (model.alpha[i] > 0 ? 'O' : 'o')
  end
  ma, mo = Array.new(w * h), 0
  multi_training.each_with_index do |e, i|
    cell = plot_cell(e.point, xmin, ymax, dx, dy, w, h)
    if cell.nil? then mo += 1
    elsif ma[cell].nil? then ma[cell] = i end
  end
  ma.each_with_index { |i, cell| multicells[cell] = multi_training[i].class_number.to_s unless i.nil? }
  lines = ["binary #{model.kernel.name} C #{fixed(model.c)}", "x #{fixed(xmin)} #{fixed(xmax)} y #{fixed(ymin)} #{fixed(ymax)} grid #{w}x#{h}"]
  lines.concat(framed_plot(binary, w))
  lines += ["cells outer_positive #{binary.count('+')} inner_positive #{binary.count('.')} inner_negative #{binary.count('-')} outer_negative #{binary.count(' ')} points #{assignments.compact.size} outside #{outside}", '', "probability #{model.kernel.name} A #{fixed(a, 6)} B #{fixed(b, 6)}"]
  lines.concat(framed_plot(probs, w))
  lines += ["levels #{levels.join(' ')}", '', 'grid_agreement']
  results.each_index do |i|
    (i + 1...results.size).each do |j|
      count = signs[i].zip(signs[j]).count { |x, y| x == y }
      lines << "#{results[i][:model].kernel.name} #{results[j][:model].kernel.name} #{count}/#{w * h} positive #{signs[i].count(1)} #{signs[j].count(1)}"
    end
  end
  lines += ['', "multiclass #{multi.kernel.name} C #{fixed(multi.c)}"]
  lines.concat(framed_plot(multicells, w))
  lines << "cells class1 #{multicells.count(' ')} class2 #{multicells.count('.')} class3 #{multicells.count(':')} disagree #{multicells.count('?')} points #{ma.compact.size} outside #{mo}"
  lines
end

def main
  training, testing, mt, me, s = read_inputs
  matrices, combinations, best, selected, ranking = cross_validate(training, s)
  results = best.each_with_index.map do |r, i|
    model = train(training.map(&:point), training.map(&:label), r[:kernel], matrices[i], r[:c], s)
    evaluate_final(model, training, testing, s.tolerance)
  end
  chosen = results[selected[:ki]]
  sections = [cv_lines(training.size, s.folds, best, selected, ranking)] + results.map { |r| r[:lines] }
  sections << training_log(chosen[:model])
  sections.concat(path_and_curve(training, testing, selected, matrices[selected[:ki]], s))
  a, b, probabilities, report = calibrate(training, testing, selected, chosen[:test_values], s.newton_iterations)
  sections << report
  comparison = results.find { |r| r[:model].kernel.kind == 'linear' }
  pv, report = pegasos(training, testing, s.pegasos, comparison)
  sections << report << mcnemar_lines(testing, results, pv)
  name, c = s.multiclass
  multi = MulticlassModels.new(mt, s.kernels.find { |k| k.name == name }, c, s)
  write_lines('output/model.txt', sections.flat_map.with_index { |section, i| i.zero? ? section : [''] + section })
  grid = [['kernel', 'C', *(1..s.folds).map { |i| "fold#{i}" }, 'correct', 'accuracy', 'support_vectors', 'passes', 'steps'].join(',')]
  combinations.each do |r|
    grid << [r[:kernel].name, fixed(r[:c]), *r[:folds].map { |f| f[:correct] }, r[:correct], ratio(r[:correct], training.size), r[:support], r[:passes], r[:steps]].join(',')
  end
  write_lines('output/cv_grid.csv', grid)
  predictions = [['id', 'label', *s.kernels.map(&:name), 'pegasos', 'predicted', 'probability'].join(',')]
  testing.each_with_index do |e, i|
    predictions << [e.id, e.label, *results.map { |r| fixed(r[:test_values][i]) }, fixed(pv[i]), sign(chosen[:test_values][i]), fixed(probabilities[i])].join(',')
  end
  write_lines('output/predictions.csv', predictions)
  write_lines('output/multiclass.txt', multiclass_lines(mt, me, multi))
  write_lines('output/decision_plot.txt', decision_plots(training, mt, results, selected, a, b, multi, s))
end

main if $PROGRAM_NAME == __FILE__
