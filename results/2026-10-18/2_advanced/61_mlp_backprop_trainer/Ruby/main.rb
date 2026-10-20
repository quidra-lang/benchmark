require_relative 'dataset'
require_relative 'network'
require_relative 'optimizers'
require_relative 'evaluation'
include Evaluation

def ordered_total(values)
  total = 0.0
  values.each { |v| total += v }
  total
end

def mean(values) = ordered_total(values) / values.size
def norm(values) = Math.sqrt(ordered_total(values.map { |v| v * v }))

def evaluate(network, theta, images)
  loss, correct = 0.0, 0
  outcomes = images.map do |image|
    cache = network.forward(theta, image)
    prediction = best_two(cache[:scores])[0]
    loss += cache[:loss]
    correct += 1 if prediction == image.label
    { id: image.id, label: image.label, predicted: prediction, confidence: cache[:scores][prediction],
      scores: cache[:scores], loss: cache[:loss], hidden: cache[:a][1...-1] }
  end
  { loss: loss / images.size, correct: correct, outcomes: outcomes }
end

def average_gradient(network, theta, images)
  result = Array.new(network.parameters, 0.0)
  images.each do |image|
    gradient, = network.gradient(theta, image)
    gradient.each_with_index { |g, i| result[i] += g }
  end
  result.map { |v| v / images.size }
end

def check_network(network, initial, training, settings)
  order = MINSTD.new(settings[:seed]).shuffle((0...training.size).to_a)
  images = order.first([settings[:batch_size], training.size].min).map { |i| training[i] }
  theta = initial.dup
  analytic = average_gradient(network, theta, images)
  checked = (0...network.parameters).step(settings[:gradient_check_stride]).to_a
  passed, h = true, 0.00001
  checked.each do |i|
    original = theta[i]
    theta[i] = original + h
    higher = evaluate(network, theta, images)[:loss]
    theta[i] = original - h
    lower = evaluate(network, theta, images)[:loss]
    theta[i] = original
    numerical = (higher - lower) / (2 * h)
    error = (analytic[i] - numerical).abs / [1, analytic[i].abs + numerical.abs].max
    passed = false unless error < 0.000001
  end
  lines = ["network #{network.name}", "parameters #{network.parameters}", "batch #{images.map(&:id).join(' ')}"]
  network.layers.each_with_index do |layer, i|
    weights = checked.count { |p| p >= layer[:weight_start] && p < layer[:weight_end] }
    biases = checked.count { |p| p >= layer[:bias_start] && p < layer[:bias_end] }
    lines << "layer #{i + 1} weights #{weights} biases #{biases}"
  end
  lines + ["checked #{checked.size}", "result #{passed ? 'PASS' : 'FAIL'}"]
end

def train_run(definition, network, initial, training, validation, settings)
  theta = initial.dup
  optimizer = Optimizer.new(definition, theta.size)
  rng, order = MINSTD.new(settings[:seed]), (0...training.size).to_a
  epochs, statuses = [], []
  best_epoch = best_loss = best_theta = nil
  saved_correct = wait = updates = 0
  stop = 'max_epochs'
  1.upto(settings[:max_epochs]) do |epoch|
    rate = optimizer.epoch_rate(epoch, settings[:lr_step], settings[:lr_gamma])
    rng.shuffle(order)
    norms = []
    order.each_slice(settings[:batch_size]) do |indices|
      grad = average_gradient(network, theta, indices.map { |i| training[i] })
      network.weight_indices.each { |i| grad[i] += definition[:decay] * theta[i] }
      norms << norm(grad)
      optimizer.update(theta, grad, rate)
      updates += 1
    end
    tr, va = evaluate(network, theta, training), evaluate(network, theta, validation)
    statuses << tr[:outcomes].map { |o| o[:predicted] == o[:label] }
    improved = best_epoch.nil? || va[:loss] < best_loss
    if improved
      best_epoch, best_loss, best_theta, saved_correct, wait = epoch, va[:loss], theta.dup, va[:correct], 0
    else
      wait += 1
    end
    epochs << { epoch: epoch, lr: rate, grad_norm: mean(norms), train_loss: tr[:loss], train_correct: tr[:correct],
                val_loss: va[:loss], val_correct: va[:correct], improved: improved }
    if wait >= settings[:patience]
      stop = 'early'
      break
    end
  end
  definition.merge(net: network, initial: initial, theta: best_theta, best_epoch: best_epoch, best_val_loss: best_loss,
                   best_val_correct: saved_correct, epochs: epochs, updates: updates, stop: stop, statuses: statuses)
end

def noisy_data(testing, rate, seed)
  rng, flipped = MINSTD.new(seed), 0
  rows = testing.map do |image|
    pixels = image.pixels.chars.map do |p|
      if rng.draw % 100 < rate
        flipped += 1
        p == '1' ? '0' : '1'
      else
        p
      end
    end.join
    Image.new(image.id, image.label, pixels, pixels.chars.map(&:to_f))
  end
  [rows, flipped]
end

def prepare_evaluation(run, training, testing, settings, noisy)
  net, theta = run.values_at(:net, :theta)
  test = evaluate(net, theta, testing)
  outcomes = test[:outcomes]
  run[:test], run[:confusion] = test, confusion(outcomes, net.classes)
  run[:top2] = outcomes.count { |o| best_two(o[:scores]).include?(o[:label]) }
  good, bad = outcomes.partition { |o| o[:predicted] == o[:label] }
  run[:confidence_correct] = good.empty? ? nil : mean(good.map { |o| o[:confidence] })
  run[:confidence_wrong] = bad.empty? ? nil : mean(bad.map { |o| o[:confidence] })
  events = training.each_index.map do |i|
    (1...run[:statuses].size).count { |e| run[:statuses][e - 1][i] && !run[:statuses][e][i] }
  end
  run[:forgetting] = [events.sum, events.count { |v| v > 0 }, training.each_index.count { |i| run[:statuses].none? { |e| e[i] } }]
  run[:norms], run[:changes] = [], []
  net.layers.each do |layer|
    indices = (layer[:weight_start]...layer[:weight_end]).to_a
    run[:norms] << norm(indices.map { |i| theta[i] })
    run[:changes] << norm(indices.map { |i| theta[i] - run[:initial][i] })
  end
  maximum = run[:epochs].flat_map { |e| [e[:train_loss], e[:val_loss]] }.max
  run[:curve] = run[:epochs].map do |e|
    row = Array.new(40, ' ')
    t, v = (39 * e[:train_loss] / maximum + 0.5).floor, (39 * e[:val_loss] / maximum + 0.5).floor
    row[t] = 't'
    row[v] = t == v ? '*' : 'v'
    format('%2d |%s|%s', e[:epoch], row.join, e[:epoch] == run[:best_epoch] ? ' best' : '')
  end
  bins = Array.new(settings[:calibration_bins]) { { count: 0, correct: 0, confidence: 0.0 } }
  outcomes.each do |o|
    bin = bins[[bins.size - 1, (o[:confidence] * bins.size).floor].min]
    bin[:count] += 1
    bin[:correct] += 1 if o[:predicted] == o[:label]
    bin[:confidence] += o[:confidence]
  end
  run[:bins], run[:ece] = bins, 0.0
  bins.each do |bin|
    count = bin[:count]
    next if count.zero?
    bin[:mean] = bin[:confidence] / count
    run[:ece] += count.to_f / testing.size * (bin[:correct].to_f / count - bin[:mean]).abs
  end
  run[:hidden] = net.layers[0...-1].each_with_index.map do |layer, l|
    means = net.classes.times.map do |k|
      rows = outcomes.select { |o| o[:label] == k }
      rows.empty? ? nil : layer[:outputs].times.map { |j| mean(rows.map { |o| o[:hidden][l][j] }) }
    end
    preferred = layer[:outputs].times.map { |j| means.each_index.select { |k| means[k] }.max_by { |k| [means[k][j], -k] } }
    zero = layer[:outputs].times.map { |j| outcomes.count { |o| o[:hidden][l][j].zero? } }
    { means: means, preferred: preferred, zeros: zero }
  end
  sorted = net.weight_indices.sort_by { |i| [theta[i].abs, i] }
  run[:pruning] = settings[:prune].map do |q|
    count = q * sorted.size / 100
    pruned = theta.dup
    sorted.first(count).each { |i| pruned[i] = 0.0 }
    [q, count, evaluate(net, pruned, testing)]
  end
  run[:noise] = settings[:noise].map { |r| [r, evaluate(net, theta, noisy[r][0])[:correct]] }
  run[:misclassified] = outcomes.each_index.select { |i| outcomes[i][:predicted] != outcomes[i][:label] }
end

def run_report(run, validation_count, test_count)
  net, test = run.values_at(:net, :test)
  events, rows, never = run[:forgetting]
  conf = ->(v) { v.nil? ? '-' : real(v) }
  lines = ["run #{run[:name]} network #{run[:network]} optimizer #{run[:optimizer]}",
           "epochs #{run[:epochs].size} best_epoch #{run[:best_epoch]} stop #{run[:stop]} updates #{run[:updates]}",
           "best_val_loss #{real(run[:best_val_loss], 6)} best_val_acc #{ratio(run[:best_val_correct], validation_count)} correct #{run[:best_val_correct]}/#{validation_count}",
           "test_loss #{real(test[:loss], 6)} test_acc #{ratio(test[:correct], test_count)} correct #{test[:correct]}/#{test_count}",
           "top2_acc #{ratio(run[:top2], test_count)} correct #{run[:top2]}/#{test_count}",
           "confidence correct #{conf.call(run[:confidence_correct])} wrong #{conf.call(run[:confidence_wrong])}",
           "forgetting events #{events} rows #{rows} never_learned #{never}",
           "weight_norms #{run[:norms].map { |v| real(v) }.join(' ')}", "weight_changes #{run[:changes].map { |v| real(v) }.join(' ')}", 'curve']
  lines.concat(run[:curve])
  lines << 'confusion'
  run[:confusion].each_with_index { |row, k| lines << "#{k}: #{row.join(' ')}" }
  net.classes.times { |k| lines << class_measures(run[:confusion], k) }
  lines << 'calibration'
  run[:bins].each_with_index do |bin, i|
    count, size = bin[:count], run[:bins].size
    lines << "bin #{i + 1} #{real(i.to_f / size, 2)} #{real((i + 1).to_f / size, 2)} count #{count} accuracy #{ratio(bin[:correct], count)} confidence #{count.zero? ? '-' : real(bin[:mean])}"
  end
  lines << "ece #{real(run[:ece])}"
  run[:hidden].each_with_index do |hidden, l|
    layer = net.layers[l]
    lines << "hidden #{l + 1} #{layer[:activation]} units #{layer[:outputs]}"
    hidden[:means].each_with_index { |values, k| lines << "class #{k} mean #{values ? values.map { |v| real(v) }.join(' ') : '-'}" }
    lines << "preferred #{hidden[:preferred].join(' ')}"
    lines << "zero_counts #{hidden[:zeros].join(' ')}" if layer[:activation] == 'RELU'
  end
  lines << 'pruning'
  run[:pruning].each do |q, count, ev|
    lines << "prune #{q} removed #{count} correct #{ev[:correct]} test_acc #{ratio(ev[:correct], test_count)} test_loss #{real(ev[:loss], 6)}"
  end
  lines << 'noise'
  run[:noise].each { |r, correct| lines << "noise #{r} correct #{correct} test_acc #{ratio(correct, test_count)}" }
  lines << (["misclassified #{run[:misclassified].size}"] + run[:misclassified].map { |i| run[:test][:outcomes][i][:id] }).join(' ')
  lines
end

def data_report(training, validation, testing, net)
  pixels = net.width * net.height
  lines = ['data', "train #{training.size} validation #{validation.size} test #{testing.size} pixels #{pixels}"]
  levels = net.classes.times.map do |k|
    rows = training.select { |e| e.label == k }
    ink = rows.sum { |e| e.pixels.count('1') }
    lines << "class #{k} train #{rows.size} validation #{validation.count { |e| e.label == k }} test #{testing.count { |e| e.label == k }} ink #{ratio(ink, rows.size)}"
    pixels.times.map { |i| rows.empty? ? 0 : [9, 10 * rows.count { |e| e.pixels[i] == '1' } / rows.size].min }
  end
  lines << "mean_images #{(0...net.classes).to_a.join(' ')}"
  lines.concat(level_maps(levels, net.width, net.height))
end

def comparison_report(runs, training, all_training, testing, settings, noisy)
  ranked = runs.each_with_index.sort_by { |run, i| [-run[:test][:correct], run[:best_val_loss], i] }.map(&:first)
  top, count = ranked[0], testing.size
  net = top[:net]
  outcomes = ->(run) { run[:test][:outcomes] }
  correct = ->(o) { o[:predicted] == o[:label] }
  top_results = outcomes.call(top)
  lines = ['comparison']
  ranked.each_with_index do |run, i|
    lines << "rank #{i + 1} #{run[:name]} correct #{run[:test][:correct]} test_acc #{ratio(run[:test][:correct], count)} best_val_loss #{real(run[:best_val_loss], 6)} test_loss #{real(run[:test][:loss], 6)} best_epoch #{run[:best_epoch]} epochs #{run[:epochs].size} updates #{run[:updates]}"
  end
  lines << 'agreement'
  runs.each do |a|
    agreements = runs.map { |b| outcomes.call(a).zip(outcomes.call(b)).count { |x, y| x[:predicted] == y[:predicted] } }
    lines << "#{a[:name]} #{agreements.join(' ')}"
  end
  lines << "mcnemar #{top[:name]}"
  ranked.drop(1).each do |run|
    b = c = 0
    top_results.zip(outcomes.call(run)).each do |x, y|
      b += 1 if correct.call(x) && !correct.call(y)
      c += 1 if !correct.call(x) && correct.call(y)
    end
    d = [(b - c).abs - 1, 0].max
    numerator, denominator = d * d, b + c
    lines << "vs #{run[:name]} b #{b} c #{c} chi2 #{denominator.zero? ? '0.0000' : ratio(numerator, denominator)} significant #{numerator * 1000 > 3841 * denominator ? 'yes' : 'no'}"
  end
  ensemble = testing.each_index.map do |i|
    votes = Array.new(net.classes, 0)
    runs.each { |run| votes[outcomes.call(run)[i][:predicted]] += 1 }
    ranked.map { |run| outcomes.call(run)[i][:predicted] }.find { |k| votes[k] == votes.max }
  end
  ec = testing.each_index.count { |i| ensemble[i] == testing[i].label }
  fixed = testing.each_index.count { |i| ensemble[i] == testing[i].label && !correct.call(top_results[i]) }
  broken = testing.each_index.count { |i| ensemble[i] != testing[i].label && correct.call(top_results[i]) }
  lines << "ensemble correct #{ec}/#{count} test_acc #{ratio(ec, count)} fixed #{fixed} broken #{broken}"
  soft = runs.select { |run| run[:net].layers[-1][:activation] == 'SOFTMAX' }
  if soft.empty?
    lines << 'soft_ensemble none'
  else
    sc = testing.each_index.count do |i|
      scores = net.classes.times.map { |k| mean(soft.map { |run| outcomes.call(run)[i][:scores][k] }) }
      best_two(scores)[0] == testing[i].label
    end
    lines << "soft_ensemble runs #{soft.size} correct #{sc}/#{count} test_acc #{ratio(sc, count)}"
  end
  settings[:noise].each { |r| lines << "noise #{r} flipped #{noisy[r][1]}" }
  pairs = []
  net.classes.times do |y|
    net.classes.times do |p|
      amount = runs.sum { |run| run[:confusion][y][p] }
      pairs << [y, p, amount] if y != p && amount > 0
    end
  end
  lines << 'confused_pairs'
  pairs.sort_by { |y, p, amount| [-amount, y, p] }.first(5).each { |y, p, amount| lines << "#{y} as #{p} count #{amount}" }
  levels = net.classes.times.map do |k|
    selected = testing.select { |e| e.label == k }
    values = Array.new(net.width * net.height, 0.0)
    selected.each do |image|
      _, _, input = net.gradient(top[:theta], image, input_gradient: true)
      input.each_with_index { |v, i| values[i] += v.abs }
    end
    values.map! { |v| v / selected.size } unless selected.empty?
    maximum = values.max
    maximum.zero? ? Array.new(values.size, 0) : values.map { |v| [9, (10 * v / maximum).floor].min }
  end
  lines += ['', "saliency #{top[:name]}", "classes #{(0...net.classes).to_a.join(' ')}"]
  lines.concat(level_maps(levels, net.width, net.height))
  lines += ['', "hardest_training_examples #{top[:name]}"]
  hard = evaluate(net, top[:theta], training)[:outcomes]
  hard.each_index.sort_by { |i| [-hard[i][:loss], i] }.first(5).each do |i|
    o = hard[i]
    lines << "#{o[:id]} label #{o[:label]} predicted #{o[:predicted]} loss #{real(o[:loss], 6)}"
  end
  lines += ['', "misclassified_examples #{top[:name]}"]
  top[:misclassified].each do |i|
    o, image = top_results[i], testing[i]
    predictions = runs.map { |run| outcomes.call(run)[i][:predicted] }
    lines << "#{image.id} label #{image.label} predicted #{o[:predicted]} confidence #{real(o[:confidence])} true_score #{real(o[:scores][image.label])} runs #{predictions.join(' ')} ensemble #{ensemble[i]}"
    distances = all_training.map { |e| e.pixels.chars.zip(image.pixels.chars).count { |a, b| a != b } }
    nearest_index = distances.each_index.min_by { |j| [distances[j], j] }
    nearest = all_training[nearest_index]
    lines << "nearest #{nearest.id} label #{nearest.label} distance #{distances[nearest_index]}"
    lines.concat(ascii_image(image.pixels, net.width))
  end
  lines
end

def write_lines(path, lines) = File.write(path, lines.join("\n") + "\n")

def main
  images, testing, definitions, weights, settings = load_inputs
  split = images.size - images.size / 5
  training, validation = images.first(split), images.drop(split)
  networks = definitions.map { |d| Network.new(d) }
  catalog = networks.to_h { |net| [net.name, net] }
  checks = networks.each_with_index.flat_map { |net, i| (i.zero? ? [] : ['']) + check_network(net, weights[net.name], training, settings) }
  runs = settings[:runs].map { |r| train_run(r, catalog[r[:network]], weights[r[:network]], training, validation, settings) }
  noisy = settings[:noise].to_h { |r| [r, noisy_data(testing, r, settings[:seed])] }
  runs.each { |run| prepare_evaluation(run, training, testing, settings, noisy) }
  log = ['run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved']
  final, predictions = [], ['run,id,label,predicted,confidence']
  runs.each_with_index do |run, i|
    run[:epochs].each do |e|
      log << [run[:name], e[:epoch], real(e[:lr], 6), real(e[:grad_norm]), real(e[:train_loss], 6), ratio(e[:train_correct], training.size), real(e[:val_loss], 6), ratio(e[:val_correct], validation.size), e[:improved] ? 1 : 0].join(',')
    end
    final << '' unless i.zero?
    final << "RUN #{run[:name]} NETWORK #{run[:network]} EPOCH #{run[:best_epoch]}"
    run[:net].layers.each_with_index do |layer, l|
      final << "LAYER #{l + 1} #{layer[:outputs]} #{layer[:inputs]}"
      w, b = run[:net].layer_values(run[:theta], layer)
      w.each { |row| final << "W #{row.map { |v| real(v) }.join(' ')}" }
      final << "B #{b.map { |v| real(v) }.join(' ')}"
    end
    run[:test][:outcomes].each { |o| predictions << [run[:name], o[:id], o[:label], o[:predicted], real(o[:confidence])].join(',') }
  end
  report = data_report(training, validation, testing, networks[0]) + ['']
  runs.each { |run| report.concat(run_report(run, validation.size, testing.size) + ['']) }
  report.concat(comparison_report(runs, training, images, testing, settings, noisy))
  write_lines('output/gradient_check.txt', checks)
  write_lines('output/training_log.csv', log)
  write_lines('output/final_weights.txt', final)
  write_lines('output/predictions.csv', predictions)
  write_lines('output/evaluation.txt', report)
end

main if $PROGRAM_NAME == __FILE__
