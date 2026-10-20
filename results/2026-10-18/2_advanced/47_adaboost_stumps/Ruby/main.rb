require_relative 'dataset'
require_relative 'adaboost'
require_relative 'variants'
require_relative 'evaluation'

module Boosting
  class Minstd
    def initialize(seed)
      @state = seed
    end

    def draw
      @state = 48_271 * @state % 2_147_483_647
    end
  end

  module_function

  def train_variant(variant, rows, params)
    case variant
    when 'discrete' then train_discrete(rows, params.rounds)
    when 'real' then train_real(rows, params.rounds, params.bins, params.smoothing, params.convergence)
    when 'gentle' then train_gentle(rows, params.rounds)
    when 'logit' then train_logit(rows, params.rounds, params.clip)
    end
  end

  def row_score(rounds, values)
    ordered_sum(rounds.map { |record| record.stump.call(values) })
  end

  def score_rows(rounds, rows)
    rows.map { |row| row_score(rounds, row.values) }
  end

  def add_round_scores(record, rows, scores)
    rows.each_with_index { |row, i| scores[i] += record.stump.call(row.values) }
  end

  def magnitude(record)
    record.stump.values.map(&:abs).max
  end

  def total_magnitude(rounds)
    ordered_sum(rounds.map { |record| magnitude(record) })
  end

  def contributions(rounds, values, features)
    result = Array.new(features, 0.0)
    rounds.each { |record| result[record.stump.feature] += record.stump.call(values) }
    result
  end

  def count_errors(rows, scores)
    rows.each_index.count { |i| prediction(scores[i]) != rows[i].label }
  end

  def loss(rows, scores, variant)
    terms = rows.each_index.map do |i|
      if variant == 'logit'
        Math.log(1.0 + Math.exp(-2.0 * rows[i].label * scores[i]))
      else
        Math.exp(-rows[i].label * scores[i])
      end
    end
    ordered_sum(terms) / rows.length
  end

  def metrics_line(kind, variant, rounds, rows, scores)
    tp = fp = tn = fn = 0
    rows.each_with_index do |row, i|
      if prediction(scores[i]) == 1
        if row.label == 1
          tp += 1
        else
          fp += 1
        end
      elsif row.label == -1
        tn += 1
      else
        fn += 1
      end
    end
    "#{kind} #{variant} rounds #{rounds} correct #{tp + tn}/#{rows.length} " \
      "accuracy #{ratio(tp + tn, rows.length)} tp #{tp} fp #{fp} tn #{tn} fn #{fn} " \
      "precision #{ratio(tp, tp + fp)} recall #{ratio(tp, tp + fn)} " \
      "f1 #{ratio(2 * tp, 2 * tp + fp + fn)} auc #{ratio(*auc(rows, scores))} " \
      "loss #{number(loss(rows, scores, variant))}"
  end

  def training_curve(rounds, training, testing, variant)
    train_scores = Array.new(training.length, 0.0)
    test_scores = Array.new(testing.length, 0.0)
    scale = 0.0
    rounds.each_with_index.map do |record, i|
      add_round_scores(record, training, train_scores)
      add_round_scores(record, testing, test_scores)
      scale += magnitude(record)
      minimum = training.each_index.map { |index| training[index].label * train_scores[index] }.min
      { round: i + 1, train_errors: count_errors(training, train_scores),
        test_errors: count_errors(testing, test_scores), train_loss: loss(training, train_scores, variant),
        test_loss: loss(testing, test_scores, variant), margin: minimum / scale }
    end
  end

  def cross_validate(rows, params)
    space = SearchSpace.new(rows)
    errors = Array.new(params.rounds, 0)
    folds = params.folds.times.map do |fold_number|
      indices = rows.each_index.select { |i| i % params.folds == fold_number }
      training_count = rows.length - indices.length
      weights = rows.each_index.map { |i| i % params.folds == fold_number ? 0.0 : 1.0 / training_count }
      model = train_discrete(rows, params.rounds, weights: weights, space: space)
      validation = indices.map { |i| rows[i] }
      scores = Array.new(validation.length, 0.0)
      fold_errors = params.rounds.times.map do |i|
        add_round_scores(model.rounds[i], validation, scores) if i < model.rounds.length
        count = count_errors(validation, scores)
        errors[i] += count
        count
      end
      { indices: indices, train: training_count, model: model, errors: fold_errors }
    end
    selected = errors.index(errors.min) + 1
    oof_scores = Array.new(rows.length, 0.0)
    folds.each do |fold|
      rounds = fold[:model].rounds.first(selected)
      fold[:indices].each { |i| oof_scores[i] = row_score(rounds, rows[i].values) }
    end
    { folds: folds, errors: errors, selected: selected, scores: oof_scores }
  end

  def magnitude_importance(rounds, feature_count, samme: false)
    scores = Array.new(feature_count, 0.0)
    counts = Array.new(feature_count, 0)
    rounds.each do |record|
      feature = record.stump.feature
      scores[feature] += samme ? record.alpha : magnitude(record)
      counts[feature] += 1
    end
    { scores: scores, counts: counts, total: ordered_sum(scores),
      order: scores.each_index.sort_by { |feature| [-scores[feature], feature] } }
  end

  def importance_lines(importance, features)
    lines = ['importance']
    importance[:order].each_with_index do |feature, i|
      score = importance[:scores][feature]
      lines << "#{i + 1} #{features[feature]} score #{number(score)} " \
               "share #{ratio(score, importance[:total])} rounds #{importance[:counts][feature]}"
    end
    lines
  end

  def analyze_variants(inputs, selected)
    inputs.params.variants.to_h do |variant|
      model = train_variant(variant, inputs.train, inputs.params)
      rounds = variant == 'discrete' ? model.rounds.first(selected) : model.rounds
      [variant, { full: model, rounds: rounds, scale: total_magnitude(rounds),
                  train: score_rows(rounds, inputs.train), test: score_rows(rounds, inputs.test),
                  curve: training_curve(model.rounds, inputs.train, inputs.test, variant),
                  importance: magnitude_importance(rounds, inputs.features.length) }]
    end
  end

  def ensemble_lines(inputs, analysis, cv)
    params = inputs.params
    lines = []
    params.variants.each do |variant|
      lines << '' unless lines.empty?
      model = analysis[variant][:full]
      header = "variant #{variant} rounds #{model.rounds.length} stop #{model.stop}"
      if variant == 'real'
        header += " bins #{params.bins} smoothing #{number(params.smoothing)} convergence #{number(params.convergence, 6)}"
      elsif variant == 'logit'
        header += " clip #{number(params.clip)}"
      end
      lines << header
      if variant == 'real'
        inputs.features.each_with_index do |feature, i|
          lines << "cuts #{feature} #{model.cuts[i].map { |cut| number(cut) }.join(' ')}"
        end
      end
      model.rounds.each_with_index do |record, i|
        stump = record.stump
        line = "round #{i + 1} feature #{inputs.features[stump.feature]}"
        if variant == 'real'
          line += " z #{number(record.z)} bound #{number(record.bound)} values "
          line += stump.values.map { |value| number(value) }.join(' ')
        else
          line += " threshold #{number(stump.thresholds[0])}"
          if variant == 'discrete'
            line += " polarity #{record.polarity} error #{number(record.error)} alpha #{number(record.alpha)} " \
                    "z #{number(record.z)} bound #{number(record.bound)}"
          else
            line += " left #{number(stump.values[0])} right #{number(stump.values[1])} error #{number(record.error)}"
            line += " loss #{number(record.loss)}" if variant == 'logit'
          end
        end
        lines << line
        next unless variant == 'discrete'

        maximum = record.weights.index(record.weights.max)
        ess = 1.0 / ordered_sum(record.weights.map { |weight| weight * weight })
        lines << "weights #{i + 1} max #{number(record.weights[maximum], 6)} " \
                 "id #{inputs.train[maximum].id} ess #{number(ess)}"
      end
      next unless variant == 'discrete'

      selected = cv[:selected]
      lines << "cv folds #{params.folds} selected #{selected} errors #{cv[:errors][selected - 1]}/#{inputs.train.length}"
      cv[:folds].each_with_index do |fold, i|
        validation = fold[:indices].length
        result = fold[:model]
        lines << "fold #{i + 1} train #{fold[:train]} validation #{validation} " \
                 "rounds #{result.rounds.length} stop #{result.stop} " \
                 "selected #{fold[:errors][selected - 1]}/#{validation} final #{fold[:errors][-1]}/#{validation}"
      end
      lines << "cv_errors #{cv[:errors].join(' ')}"
    end
    lines
  end

  def error_curve_lines(inputs, analysis, samme_curve)
    lines = ['variant,round,train_error,test_error,train_loss,test_loss,min_margin']
    inputs.params.variants.each do |variant|
      analysis[variant][:curve].each do |point|
        lines << [variant, point[:round], ratio(point[:train_errors], inputs.train.length),
                  ratio(point[:test_errors], inputs.test.length), number(point[:train_loss]),
                  number(point[:test_loss]), number(point[:margin])].join(',')
      end
    end
    samme_curve.each do |round, training_errors, testing_errors|
      lines << "samme,#{round},#{ratio(training_errors, inputs.multi_train.length)}," \
               "#{ratio(testing_errors, inputs.multi_test.length)},-,-,-"
    end
    lines
  end

  def prediction_lines(inputs, analysis)
    lines = [(['id', 'variant', 'score', 'label'] + inputs.features).join(',')]
    inputs.test.each_with_index do |row, i|
      inputs.params.variants.each do |variant|
        result = analysis[variant]
        score = result[:test][i]
        parts = contributions(result[:rounds], row.values, inputs.features.length)
        lines << ([row.id, variant, number(score), prediction(score)] + parts.map { |part| number(part) }).join(',')
      end
    end
    lines
  end

  def roc_lines(inputs, analysis)
    lines = ['variant,threshold,tp,fp']
    inputs.params.variants.each do |variant|
      scores = analysis[variant][:test]
      scores.uniq.sort.reverse_each do |threshold|
        tp = fp = 0
        inputs.test.each_with_index do |row, i|
          next if scores[i] < threshold

          if row.label == 1
            tp += 1
          else
            fp += 1
          end
        end
        lines << "#{variant},#{number(threshold)},#{tp},#{fp}"
      end
    end
    lines
  end

  def permutation_importance(rounds, rows, feature_count, repeats, generator)
    base = rows.length - count_errors(rows, score_rows(rounds, rows))
    results = feature_count.times.map do |feature|
      counts = repeats.times.map do
        permutation = rows.each_index.to_a
        (rows.length - 1).downto(1) do |i|
          other = generator.draw % (i + 1)
          permutation[i], permutation[other] = permutation[other], permutation[i]
        end
        rows.each_index.count do |i|
          values = rows[i].values.dup
          values[feature] = rows[permutation[i]].values[feature]
          prediction(row_score(rounds, values)) == rows[i].label
        end
      end
      drop = 0
      counts.each { |count| drop += base - count }
      [feature, drop, counts.min, counts.max]
    end
    [base, results.sort_by { |feature, drop, _minimum, _maximum| [-drop, feature] }]
  end

  def margin_lines(inputs, analysis)
    lines = []
    repeats, seed = inputs.params.permutation
    generator = Minstd.new(seed)
    inputs.params.variants.each do |variant|
      lines << '' unless lines.empty?
      result = analysis[variant]
      train_margins = inputs.train.each_index.map { |i| inputs.train[i].label * result[:train][i] / result[:scale] }
      test_margins = inputs.test.each_index.map { |i| inputs.test[i].label * result[:test][i] / result[:scale] }
      lines << "variant #{variant} rounds #{result[:rounds].length} scale #{number(result[:scale])}"
      lines << "train min #{number(train_margins.min)} mean #{number(ordered_sum(train_margins) / inputs.train.length)}"
      inputs.params.margins.each do |threshold|
        count = count_at_most(train_margins, threshold)
        lines << "train le #{number(threshold)} #{count}/#{inputs.train.length} #{ratio(count, inputs.train.length)}"
      end
      histogram = Array.new(20, 0)
      train_margins.each { |margin| histogram[[19, ((margin + 1.0) * 10.0).floor].min] += 1 }
      lines << "histogram #{histogram.join(' ')}"
      hardest = inputs.train.each_index.sort_by { |i| [train_margins[i], i] }.first(5)
      hardest.each do |i|
        lines << "hardest #{inputs.train[i].id} label #{inputs.train[i].label} margin #{number(train_margins[i])}"
      end
      lines << "test min #{number(test_margins.min)} mean #{number(ordered_sum(test_margins) / inputs.test.length)}"
      inputs.params.margins.each do |threshold|
        count = count_at_most(test_margins, threshold)
        lines << "test le #{number(threshold)} #{count}/#{inputs.test.length} #{ratio(count, inputs.test.length)}"
      end
      inputs.params.margins.each do |threshold|
        confident = test_margins.each_index.select { |i| test_margins[i].abs > threshold }
        correct = confident.count { |i| prediction(result[:test][i]) == inputs.test[i].label }
        lines << "test confident #{number(threshold)} #{confident.length}/#{inputs.test.length} " \
                 "correct #{correct}/#{confident.length} #{ratio(correct, confident.length)}"
      end
      lines.concat(importance_lines(result[:importance], inputs.features))
      base, permutation = permutation_importance(result[:rounds], inputs.test, inputs.features.length, repeats, generator)
      lines << "permutation repeats #{repeats} base #{base}/#{inputs.test.length}"
      permutation.each_with_index do |(feature, drop, minimum, maximum), i|
        lines << "#{i + 1} #{inputs.features[feature]} drop #{ratio(drop, repeats * inputs.test.length)} " \
                 "min #{minimum}/#{inputs.test.length} max #{maximum}/#{inputs.test.length}"
      end
    end
    lines
  end

  def shape_lines(inputs, analysis)
    lines = []
    inputs.params.variants.each do |variant|
      lines << '' unless lines.empty?
      rounds = analysis[variant][:rounds]
      lines << "variant #{variant} rounds #{rounds.length}"
      inputs.features.each_with_index do |name, feature|
        collected = rounds.select { |record| record.stump.feature == feature }
        cuts = collected.flat_map { |record| record.stump.thresholds }.uniq.sort
        values = [ordered_sum(collected.map { |record| record.stump.values[0] })]
        cuts.each do |cut|
          values << ordered_sum(collected.map do |record|
            index = record.stump.thresholds.count { |threshold| threshold <= cut }
            record.stump.values[index]
          end)
        end
        lines << "feature #{name} rounds #{collected.length} cuts #{cuts.length} range #{number(values.max - values.min)}"
        values.each_with_index do |value, i|
          lower = i.zero? ? '-inf' : number(cuts[i - 1])
          upper = i == cuts.length ? 'inf' : number(cuts[i])
          lines << "interval #{lower} #{upper} value #{number(value)}"
        end
      end
    end
    lines
  end

  def calibration_lines(variant, rows, scores)
    counts = Array.new(5, 0)
    totals = Array.new(5, 0.0)
    positives = Array.new(5, 0)
    brier = 0.0
    rows.each_with_index do |row, i|
      probability = 1.0 / (1.0 + Math.exp(-2.0 * scores[i]))
      target = row.label == 1 ? 1 : 0
      difference = probability - target
      brier += difference * difference
      index = [4, (probability * 5.0).floor].min
      counts[index] += 1
      totals[index] += probability
      positives[index] += target
    end
    lines = ["calibration #{variant} brier #{number(brier / rows.length)}"]
    ranges = %w[0.0-0.2 0.2-0.4 0.4-0.6 0.6-0.8 0.8-1.0]
    ranges.each_with_index do |range, i|
      lines << "bin #{range} count #{counts[i]} mean #{ratio(totals[i], counts[i])} positives #{positives[i]}"
    end
    lines
  end

  def comparison_lines(inputs, analysis)
    predictions = inputs.params.variants.to_h { |variant| [variant, analysis[variant][:test].map { |score| prediction(score) }] }
    all_wrong = inputs.test.each_index.select do |i|
      inputs.params.variants.all? { |variant| predictions[variant][i] != inputs.test[i].label }
    end
    lines = [(['all_wrong', all_wrong.length] + all_wrong.map { |i| inputs.test[i].id }).join(' '), 'agreement']
    inputs.params.variants.combination(2) do |first, second|
      agree = only_first = only_second = 0
      inputs.test.each_with_index do |row, i|
        a = predictions[first][i]
        b = predictions[second][i]
        agree += 1 if a == b
        only_first += 1 if a == row.label && b != row.label
        only_second += 1 if b == row.label && a != row.label
      end
      difference = (only_first - only_second).abs - 1
      lines << "#{first} #{second} agree #{agree}/#{inputs.test.length} only_first #{only_first} " \
               "only_second #{only_second} chi2 #{ratio(difference * difference, only_first + only_second)}"
    end
    lines
  end

  def bootstrap_lines(inputs, analysis)
    samples, seed = inputs.params.bootstrap
    generator = Minstd.new(seed)
    correct = inputs.params.variants.to_h do |variant|
      [variant, inputs.test.each_index.map { |i| prediction(analysis[variant][:test][i]) == inputs.test[i].label }]
    end
    counts = inputs.params.variants.to_h { |variant| [variant, []] }
    samples.times do
      selected = Array.new(inputs.test.length) { generator.draw % inputs.test.length }
      inputs.params.variants.each { |variant| counts[variant] << selected.count { |i| correct[variant][i] } }
    end
    lines = ["bootstrap samples #{samples} seed #{seed}"]
    trim = samples / 40
    inputs.params.variants.each do |variant|
      ordered = counts[variant].sort
      total = 0
      counts[variant].each { |count| total += count }
      lines << "#{variant} mean #{ratio(total, samples * inputs.test.length)} " \
               "low #{ratio(ordered[trim], inputs.test.length)} high #{ratio(ordered[samples - trim - 1], inputs.test.length)}"
    end
    inputs.params.variants.combination(2) do |first, second|
      wins = ties = losses = 0
      samples.times do |i|
        a = counts[first][i]
        b = counts[second][i]
        wins += 1 if a > b
        ties += 1 if a == b
        losses += 1 if a < b
      end
      lines << "#{first} #{second} first #{wins} tie #{ties} second #{losses}"
    end
    lines
  end

  def feature_summary(rows, feature)
    values = rows.map { |row| row.values[feature] }
    "#{number(values.min)} #{number(values.max)} #{number(ordered_sum(values) / values.length)} #{values.uniq.length}"
  end

  def summary_lines(inputs, analysis, cv)
    training = inputs.train
    testing = inputs.test
    params = inputs.params
    lines = ["data train #{training.length} test #{testing.length} features #{inputs.features.length} " \
             "positives #{training.count { |row| row.label == 1 }} #{testing.count { |row| row.label == 1 }}"]
    inputs.features.each_with_index do |name, feature|
      lines << "feature #{name} train #{feature_summary(training, feature)} test #{feature_summary(testing, feature)}"
    end
    selected = cv[:selected]
    errors = cv[:errors][selected - 1]
    lines << "cv selected #{selected} errors #{errors}/#{training.length} rate #{ratio(errors, training.length)}"
    lines << metrics_line('oof', 'discrete', selected, training, cv[:scores])
    committee_train = Array.new(training.length, 0.0)
    committee_test = Array.new(testing.length, 0.0)
    committee_rounds = 0
    params.variants.each do |variant|
      result = analysis[variant]
      rounds = result[:rounds].length
      lines << metrics_line('train', variant, rounds, training, result[:train])
      lines << metrics_line('test', variant, rounds, testing, result[:test])
      committee_rounds += rounds
      result[:train].each_with_index { |score, i| committee_train[i] += score / result[:scale] }
      result[:test].each_with_index { |score, i| committee_test[i] += score / result[:scale] }
    end
    lines << metrics_line('train', 'committee', committee_rounds, training, committee_train)
    lines << metrics_line('test', 'committee', committee_rounds, testing, committee_test)
    params.variants.each do |variant|
      curve = analysis[variant][:curve]
      train_minimum = curve.min_by { |point| [point[:train_errors], point[:round]] }
      test_minimum = curve.min_by { |point| [point[:test_errors], point[:round]] }
      lines << "curve #{variant} rounds #{curve.length} train_min #{train_minimum[:train_errors]}/#{training.length} " \
               "at #{train_minimum[:round]} test_min #{test_minimum[:test_errors]}/#{testing.length} at #{test_minimum[:round]}"
    end
    lines.concat(comparison_lines(inputs, analysis))
    lines.concat(bootstrap_lines(inputs, analysis))
    params.variants.each { |variant| lines.concat(calibration_lines(variant, testing, analysis[variant][:test])) }
    lines
  end

  def class_prediction(scores)
    scores.index(scores.max) + 1
  end

  def class_errors(rows, predictions)
    rows.each_index.count { |i| rows[i].label != predictions[i] }
  end

  def samme_progression(rounds, training, testing, classes)
    train_scores = Array.new(training.length) { Array.new(classes, 0.0) }
    test_scores = Array.new(testing.length) { Array.new(classes, 0.0) }
    curve = rounds.each_with_index.map do |record, i|
      [[training, train_scores], [testing, test_scores]].each do |rows, scores|
        rows.each_with_index { |row, index| scores[index][record.stump.call(row.values) - 1] += record.alpha }
      end
      train_predictions = train_scores.map { |scores| class_prediction(scores) }
      test_predictions = test_scores.map { |scores| class_prediction(scores) }
      [i + 1, class_errors(training, train_predictions), class_errors(testing, test_predictions)]
    end
    [train_scores, test_scores, curve]
  end

  def confusion_lines(rows, predictions, classes)
    matrix = confusion(rows, predictions, classes)
    lines = ['confusion'] + matrix.map { |row| row.join(' ') }
    classes.times do |i|
      predicted = 0
      actual = 0
      matrix.each { |row| predicted += row[i] }
      matrix[i].each { |count| actual += count }
      lines << "class #{i + 1} precision #{ratio(matrix[i][i], predicted)} recall #{ratio(matrix[i][i], actual)}"
    end
    lines
  end

  def class_error_lines(training, testing, train_predictions, test_predictions)
    [['train', training, train_predictions], ['test', testing, test_predictions]].map do |kind, rows, predictions|
      count = class_errors(rows, predictions)
      "#{kind} errors #{count}/#{rows.length} rate #{ratio(count, rows.length)}"
    end
  end

  def multiclass_report(inputs)
    training = inputs.multi_train
    testing = inputs.multi_test
    params = inputs.params
    model = train_samme(training, params.samme_rounds, params.classes)
    train_scores, test_scores, curve = samme_progression(model.rounds, training, testing, params.classes)
    train_predictions = train_scores.map { |scores| class_prediction(scores) }
    test_predictions = test_scores.map { |scores| class_prediction(scores) }
    lines = ["samme classes #{params.classes} train #{training.length} test #{testing.length} " \
             "rounds #{model.rounds.length} stop #{model.stop}"]
    model.rounds.each_with_index do |record, i|
      stump = record.stump
      lines << "round #{i + 1} feature #{inputs.multi_features[stump.feature]} threshold #{number(stump.thresholds[0])} " \
               "left #{stump.values[0]} right #{stump.values[1]} error #{number(record.error)} alpha #{number(record.alpha)}"
    end
    lines.concat(class_error_lines(training, testing, train_predictions, test_predictions))
    lines.concat(confusion_lines(testing, test_predictions, params.classes))
    importance = magnitude_importance(model.rounds, inputs.multi_features.length, samme: true)
    lines.concat(importance_lines(importance, inputs.multi_features))
    lines.concat(['', "ovr classes #{params.classes} rounds #{params.samme_rounds}"])
    ovr_train_scores = []
    ovr_test_scores = []
    (1..params.classes).each do |klass|
      binary_training = training.map { |row| row.with(label: row.label == klass ? 1 : -1) }
      binary_testing = testing.map { |row| row.with(label: row.label == klass ? 1 : -1) }
      binary_model = train_discrete(binary_training, params.samme_rounds)
      binary_train_scores = score_rows(binary_model.rounds, binary_training)
      binary_test_scores = score_rows(binary_model.rounds, binary_testing)
      ovr_train_scores << binary_train_scores
      ovr_test_scores << binary_test_scores
      positives = training.count { |row| row.label == klass }
      lines << "class #{klass} rounds #{binary_model.rounds.length} stop #{binary_model.stop} positives #{positives} " \
               "train_errors #{count_errors(binary_training, binary_train_scores)}/#{training.length} " \
               "test_errors #{count_errors(binary_testing, binary_test_scores)}/#{testing.length}"
    end
    ovr_train_predictions = ovr_train_scores.transpose.map { |scores| class_prediction(scores) }
    ovr_test_predictions = ovr_test_scores.transpose.map { |scores| class_prediction(scores) }
    lines.concat(class_error_lines(training, testing, ovr_train_predictions, ovr_test_predictions))
    lines.concat(confusion_lines(testing, ovr_test_predictions, params.classes))
    agreement = test_predictions.each_index.count { |i| test_predictions[i] == ovr_test_predictions[i] }
    lines.concat(["agreement #{agreement}/#{testing.length}", '', 'predictions'])
    testing.each_with_index do |row, i|
      lines << "#{row.id} class #{row.label} samme #{test_predictions[i]} ovr #{ovr_test_predictions[i]} scores " \
               "#{test_scores[i].map { |score| number(score) }.join(' ')}"
    end
    [lines, curve]
  end

  def model_errors(model, training, testing)
    [count_errors(training, score_rows(model.rounds, training)),
     count_errors(testing, score_rows(model.rounds, testing))]
  end

  def test_minimum(rounds, testing)
    scores = Array.new(testing.length, 0.0)
    counts = rounds.map do |record|
      add_round_scores(record, testing, scores)
      count_errors(testing, scores)
    end
    minimum = counts.min
    [minimum, counts.index(minimum) + 1]
  end

  def experiment_lines(inputs, analysis, selected)
    training = inputs.train
    testing = inputs.test
    params = inputs.params
    lines = []
    params.sizes.each do |percentage|
      size = training.length * percentage / 100
      subset = training.first(size)
      lines << "size #{percentage} rows #{size}"
      params.variants.each do |variant|
        model = train_variant(variant, subset, params)
        train_errors, test_errors = model_errors(model, subset, testing)
        lines << "#{variant} rounds #{model.rounds.length} stop #{model.stop} " \
                 "train_errors #{train_errors}/#{size} test_errors #{test_errors}/#{testing.length}"
      end
    end
    params.shrinkage.each do |shrinkage|
      model = train_discrete(training, params.rounds, shrinkage: shrinkage)
      train_errors, test_errors = model_errors(model, training, testing)
      minimum, at = test_minimum(model.rounds, testing)
      lines << "shrinkage #{number(shrinkage)} rounds #{model.rounds.length} stop #{model.stop} " \
               "train_errors #{train_errors}/#{training.length} test_errors #{test_errors}/#{testing.length} " \
               "test_min #{minimum}/#{testing.length} at #{at}"
    end
    ranked = analysis['discrete'][:importance][:order]
    (1..inputs.features.length).each do |count|
      features = ranked.first(count).sort
      reduced_training = training.map { |row| row.with(values: features.map { |feature| row.values[feature] }) }
      reduced_testing = testing.map { |row| row.with(values: features.map { |feature| row.values[feature] }) }
      model = train_discrete(reduced_training, selected)
      train_errors, test_errors = model_errors(model, reduced_training, reduced_testing)
      names = features.map { |feature| inputs.features[feature] }.join(' ')
      lines << "top #{count} features #{names} rounds #{model.rounds.length} " \
               "train_errors #{train_errors}/#{training.length} test_errors #{test_errors}/#{testing.length}"
    end
    params.noise.each do |percentage|
      flipped_count = training.length * percentage / 100
      generator = Minstd.new(params.noise_seed)
      permutation = training.each_index.to_a
      flipped_count.times do |i|
        other = generator.draw % (training.length - i) + i
        permutation[i], permutation[other] = permutation[other], permutation[i]
      end
      flipped = Array.new(training.length, false)
      permutation.first(flipped_count).each { |i| flipped[i] = true }
      noisy = training.each_with_index.map { |row, i| flipped[i] ? row.with(label: -row.label) : row }
      lines << "noise #{percentage} flipped #{flipped_count}"
      params.variants.each do |variant|
        model = train_variant(variant, noisy, params)
        train_errors, test_errors = model_errors(model, noisy, testing)
        minimum, at = test_minimum(model.rounds, testing)
        flipped_weight = 0.0
        model.rounds[-1].weights.each_with_index { |weight, i| flipped_weight += weight if flipped[i] }
        lines << "#{variant} rounds #{model.rounds.length} stop #{model.stop} " \
                 "train_errors #{train_errors}/#{training.length} test_errors #{test_errors}/#{testing.length} " \
                 "test_min #{minimum}/#{testing.length} at #{at} flipped_weight #{number(flipped_weight)}"
      end
    end
    lines
  end

  def main
    inputs = read_inputs
    cv = cross_validate(inputs.train, inputs.params)
    analysis = analyze_variants(inputs, cv[:selected])
    samme_lines, samme_curve = multiclass_report(inputs)
    reports = {
      'ensemble.txt' => ensemble_lines(inputs, analysis, cv),
      'error_curve.csv' => error_curve_lines(inputs, analysis, samme_curve),
      'predictions.csv' => prediction_lines(inputs, analysis),
      'roc.csv' => roc_lines(inputs, analysis),
      'margins.txt' => margin_lines(inputs, analysis),
      'shapes.txt' => shape_lines(inputs, analysis),
      'samme.txt' => samme_lines,
      'summary.txt' => summary_lines(inputs, analysis, cv),
      'experiments.txt' => experiment_lines(inputs, analysis, cv[:selected])
    }
    Dir.mkdir('output') unless Dir.exist?('output')
    reports.each { |filename, lines| write_lines(File.join('output', filename), lines) }
  end
end

Boosting.main if __FILE__ == $PROGRAM_NAME
