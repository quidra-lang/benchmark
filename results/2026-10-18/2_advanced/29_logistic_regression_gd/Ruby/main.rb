require 'fileutils'
require_relative 'dataset'
require_relative 'logistic'
require_relative 'optimizers'
require_relative 'softmax'
require_relative 'metrics'

class LogisticAnalysis
  MODELS = %w[gd sgd newton].freeze

  def initialize
    @names, @training, @test, @settings = Dataset.read
    @n = @training.length
    @m = @test.length
    @d = @names.length
    @classes = @training.map(&:label).max + 1
    @tuples = Dataset.tuples(@d, @settings[:degree])
    @feature_names = @tuples.map { |tuple| tuple.map { |index| @names[index] }.join('*') }
    @p = @tuples.length
    @expanded_training = @training.map { |row| Dataset.expand(row.values, @tuples) }
    @expanded_test = @test.map { |row| Dataset.expand(row.values, @tuples) }
    @means, @deviations = Dataset.statistics(@expanded_training)
    @x_train = Dataset.standardize(@expanded_training, @means, @deviations)
    @x_test = Dataset.standardize(@expanded_test, @means, @deviations)
    @y_train = @training.map { |row| row.label == @settings[:positive] ? 1 : 0 }
    @y_test = @test.map { |row| row.label == @settings[:positive] ? 1 : 0 }
    @labels = @training.map(&:label)
    @positive = @y_test.count(1)
    @negative = @m - @positive
    @base_mean = @means.first(@d)
    @cv_cache = {}
  end

  def total(values)
    result = 0.0
    values.each { |value| result += value }
    result
  end

  def mean(values)
    total(values) / values.length.to_f
  end

  def length(vector)
    Math.sqrt(total(vector.map { |value| value * value }))
  end

  def real(value, digits = 4)
    Metrics.real(value, digits)
  end

  def ratio(numerator, denominator)
    Metrics.ratio(numerator, denominator)
  end

  def fraction(pair)
    Metrics.fraction(pair)
  end

  def correct(probabilities, targets, threshold = @settings[:threshold])
    probabilities.each_index.count { |index| (probabilities[index] >= threshold ? 1 : 0) == targets[index] }
  end

  def cross_validate(lambda, count)
    key = [lambda, count]
    return @cv_cache[key] if @cv_cache.key?(key)

    losses = Array.new(@n)
    probabilities = Array.new(@n)
    fold_losses = []
    5.times do |fold|
      train_indices = (0...@n).reject { |index| index % 5 == fold }
      valid_indices = (0...@n).select { |index| index % 5 == fold }
      rows = train_indices.map { |index| @expanded_training[index] }
      means, deviations = Dataset.statistics(rows, count)
      vectors = Dataset.standardize(rows, means, deviations)
      targets = train_indices.map { |index| @y_train[index] }
      weights = Optimizers.newton(vectors, targets, lambda).last[1]
      validation = Dataset.standardize(valid_indices.map { |index| @expanded_training[index] }, means, deviations)
      valid_indices.each_with_index do |index, position|
        score = Logistic.score(weights, validation[position])
        losses[index] = Logistic.loss(score, @y_train[index])
        probabilities[index] = Logistic.probability(score)
      end
      fold_losses << mean(valid_indices.map { |index| losses[index] })
    end
    @cv_cache[key] = {
      lambda: lambda, folds: fold_losses, loss: mean(losses), probabilities: probabilities,
      errors: @n - correct(probabilities, @y_train)
    }
  end

  def train_models
    @cross_validation = @settings[:lambdas].map { |lambda| cross_validate(lambda, @p) }
    @selected = @cross_validation.min_by { |entry| [entry[:loss], -entry[:lambda]] }
    @lambda = @selected[:lambda]
    average = mean(@selected[:folds])
    variance = total(@selected[:folds].map { |value| (value - average) * (value - average) }) / 4.0
    @standard_error = Math.sqrt(variance) / Math.sqrt(5.0)
    @lambda_one_se = @cross_validation.select do |entry|
      entry[:loss] <= @selected[:loss] + @standard_error
    end.last[:lambda]
    @path = @settings[:lambdas].to_h do |lambda|
      [lambda, Optimizers.newton(@x_train, @y_train, lambda)]
    end
    @checkpoints = {
      'gd' => Optimizers.gradient_descent(@x_train, @y_train, @lambda, *@settings[:gd]),
      'sgd' => Optimizers.stochastic(@x_train, @y_train, @lambda, *@settings[:sgd]),
      'newton' => @path[@lambda]
    }
    @weights = @checkpoints.transform_values { |checkpoints| checkpoints.last[1] }
    @probabilities = @weights.transform_values { |weights| Logistic.probabilities(weights, @x_test) }
    @predictions = @probabilities.transform_values do |values|
      values.map { |value| value >= @settings[:threshold] ? 1 : 0 }
    end
    @soft_checkpoints = Softmax.train(@x_train, @labels, @classes, *@settings[:softmax])
    @soft_weights = @soft_checkpoints.last[1]
    @soft_probabilities = @x_test.map { |row| Softmax.probabilities(@soft_weights, row) }
    @soft_predictions = @soft_probabilities.map { |values| Softmax.predict(values) }
    @influence = influence(@weights['newton'], @x_train, @y_train, @lambda)
    @original_newton = original_weights(@weights['newton'])
  end

  def inverse(matrix)
    lower = Optimizers.cholesky(matrix)
    size = matrix.length
    result = Array.new(size) { Array.new(size, 0.0) }
    size.times do |column|
      basis = Array.new(size, 0.0)
      basis[column] = 1.0
      solution = Optimizers.solve(lower, basis)
      size.times { |row| result[row][column] = solution[row] }
    end
    result
  end

  def influence(weights, vectors, targets, lambda)
    matrix = inverse(Logistic.hessian(weights, vectors, lambda))
    probabilities = Logistic.probabilities(weights, vectors)
    rows = vectors.each_with_index.map do |vector, index|
      probability = probabilities[index]
      variance = probability * (1.0 - probability)
      quadratic = 0.0
      vector.each_index do |first|
        vector.each_index { |second| quadratic += vector[first] * matrix[first][second] * vector[second] }
      end
      leverage = variance * quadratic / vectors.length.to_f
      pearson = (targets[index] - probability) / Math.sqrt(variance)
      residual = pearson / Math.sqrt(1.0 - leverage)
      cook = pearson * pearson * leverage / (vector.length * ((1.0 - leverage) * (1.0 - leverage)))
      { probability: probability, leverage: leverage, residual: residual, cook: cook }
    end
    edf = total(rows.map { |row| row[:leverage] })
    loss = Logistic.average_loss(weights, vectors, targets)
    deviance = 2 * vectors.length * loss
    { inverse: matrix, rows: rows, edf: edf, loss: loss, deviance: deviance,
      aic: deviance + 2 * edf, bic: deviance + Math.log(vectors.length) * edf }
  end

  def original_weights(weights)
    converted = (1...weights.length).map { |index| weights[index] / @deviations[index - 1] }
    adjustment = total(converted.each_with_index.map { |value, index| value * @means[index] })
    [weights[0] - adjustment] + converted
  end

  def separate(parts)
    parts.each_with_index.flat_map { |part, index| index.zero? ? part : [''] + part }
  end

  def term_lines(weights)
    original = original_weights(weights)
    (['intercept'] + @feature_names).each_with_index.map do |name, index|
      "term #{name} standardized #{real(weights[index])} original #{real(original[index])}"
    end
  end

  def weights_lines
    correlation = Array.new(@p) do |first|
      Array.new(@p) do |second|
        total(@x_train.map { |row| row[first + 1] * row[second + 1] }) / (@n - 1).to_f
      end
    end
    vif = inverse(correlation)
    features = ["features #{@d} degree #{@settings[:degree]} expanded #{@p}", 'standardization']
    @feature_names.each_with_index do |name, index|
      features << "#{name} mean #{real(@means[index], 6)} sd #{real(@deviations[index], 6)} vif #{real(vif[index][index])}"
    end
    features << 'correlation'
    correlation.each { |row| features << row.map { |value| real(value) }.join(' ') }
    parts = [features]
    MODELS.each do |name|
      weights = @weights[name]
      lines = ["model #{name} lambda #{real(@lambda)}"] + term_lines(weights)
      lines << "norm #{real(length(weights.drop(1)))}"
      unless name == 'newton'
        difference = weights.each_index.map { |index| weights[index] - @weights['newton'][index] }
        lines << "distance_to_newton #{real(length(difference), 6)}"
      end
      parts << lines
    end
    coefficients = ["coefficients newton lambda #{real(@lambda)}"]
    (['intercept'] + @feature_names).each_with_index do |name, index|
      weight = @weights['newton'][index]
      error = Math.sqrt(@influence[:inverse][index][index] / @n.to_f)
      coefficients << "#{name} weight #{real(weight)} se #{real(error)} z #{real(weight / error)} lower #{real(weight - 1.96 * error)} upper #{real(weight + 1.96 * error)} odds_ratio #{real(Math.exp(weight))}"
    end
    parts << coefficients
    softmax = ["model softmax lambda #{real(@settings[:softmax][2])}"]
    @soft_weights.each_with_index do |weights, klass|
      softmax << "class #{klass}"
      softmax.concat(term_lines(weights))
    end
    parts << softmax
    separate(parts)
  end

  def trace_lines
    lines = ['optimizer,iteration,loss,gradient_norm,test_loss']
    MODELS.each do |name|
      @checkpoints[name].each do |iteration, weights|
        objective = Logistic.objective(weights, @x_train, @y_train, @lambda)
        gradient = Logistic.gradient(weights, @x_train, @y_train, @lambda)
        test_loss = Logistic.average_loss(weights, @x_test, @y_test)
        lines << [name, iteration, real(objective, 6), real(length(gradient), 6), real(test_loss, 6)].join(',')
      end
    end
    lambda = @settings[:softmax][2]
    @soft_checkpoints.each do |iteration, weights|
      objective = Softmax.objective(weights, @x_train, @labels, lambda)
      gradient = Softmax.gradient(weights, @x_train, @labels, lambda).flatten
      loss = Softmax.average_loss(weights, @x_test, @test.map(&:label))
      lines << ['softmax', iteration, real(objective, 6), real(length(gradient), 6), real(loss, 6)].join(',')
    end
    lines
  end

  def prediction_lines
    lines = ['id,model,probability,predicted,actual']
    MODELS.each do |name|
      @test.each_with_index do |row, index|
        lines << [row.id, name, real(@probabilities[name][index], 6), @predictions[name][index], @y_test[index]].join(',')
      end
    end
    @test.each_with_index do |row, index|
      klass = @soft_predictions[index]
      lines << [row.id, 'softmax', real(@soft_probabilities[index][klass], 6), klass, row.label].join(',')
    end
    lines
  end

  def data_section
    train_counts = (0...@classes).map { |klass| @labels.count(klass) }
    test_counts = (0...@classes).map { |klass| @test.count { |row| row.label == klass } }
    ["data train #{@n} test #{@m} base_features #{@d} degree #{@settings[:degree]} features #{@p}",
     "binary positive_class #{@settings[:positive]} train #{@y_train.count(1)}/#{@n} test #{@positive}/#{@m}",
     "classes #{@classes} train #{train_counts.join(' ')} test #{test_counts.join(' ')}"]
  end

  def validation_section
    lines = ['cross_validation folds 5 newton_iterations 10']
    @cross_validation.each do |entry|
      folds = entry[:folds].map { |value| real(value, 6) }.join(' ')
      lines << "lambda #{real(entry[:lambda])} fold_loss #{folds} cv_loss #{real(entry[:loss], 6)} errors #{entry[:errors]}/#{@n}"
    end
    lines << "selected lambda #{real(@lambda)} cv_loss #{real(@selected[:loss], 6)} se #{real(@standard_error, 6)} lambda_1se #{real(@lambda_one_se)}"
    counts = Metrics.confusion(@selected[:probabilities], @y_train, @settings[:threshold])
    auc = Metrics.auc(@selected[:probabilities], @y_train)
    lines << "out_of_fold tp #{counts[:tp]} fp #{counts[:fp]} tn #{counts[:tn]} fn #{counts[:fn]} accuracy #{ratio(counts[:tp] + counts[:tn], @n)} auc #{fraction(auc)}"
    lines
  end

  def path_section
    lines = ['lambda_path']
    @path.each do |lambda, checkpoints|
      weights = checkpoints.last[1]
      train_loss = Logistic.average_loss(weights, @x_train, @y_train)
      test_loss = Logistic.average_loss(weights, @x_test, @y_test)
      train_correct = correct(Logistic.probabilities(weights, @x_train), @y_train)
      test_correct = correct(Logistic.probabilities(weights, @x_test), @y_test)
      objective = Logistic.objective(weights, @x_train, @y_train, lambda)
      lines << "lambda #{real(lambda)} objective #{real(objective, 6)} train_loss #{real(train_loss, 6)} test_loss #{real(test_loss, 6)} train_accuracy #{ratio(train_correct, @n)} test_accuracy #{ratio(test_correct, @m)} norm #{real(length(weights.drop(1)))}"
    end
    lines
  end

  def degree_section
    lines = ["degrees lambda #{real(@lambda)}"]
    (1..@settings[:degree]).each do |degree|
      count = @tuples.count { |tuple| tuple.length <= degree }
      training = @x_train.map { |row| row.first(count + 1) }
      test = @x_test.map { |row| row.first(count + 1) }
      weights = Optimizers.newton(training, @y_train, @lambda).last[1]
      cv = cross_validate(@lambda, count)
      measures = influence(weights, training, @y_train, @lambda)
      probabilities = Logistic.probabilities(weights, test)
      test_loss = Logistic.average_loss(weights, test, @y_test)
      auc = Metrics.auc(probabilities, @y_test)
      lines << "degree #{degree} features #{count} cv_loss #{real(cv[:loss], 6)} train_loss #{real(measures[:loss], 6)} test_loss #{real(test_loss, 6)} test_accuracy #{ratio(correct(probabilities, @y_test), @m)} auc #{fraction(auc)} edf #{real(measures[:edf])} aic #{real(measures[:aic])} bic #{real(measures[:bic])}"
    end
    lines
  end

  def learning_section
    lines = ["learning_curve lambda #{real(@lambda)}"]
    (1..4).each do |step|
      size = step * @n / 4
      rows = @expanded_training.first(size)
      means, deviations = Dataset.statistics(rows)
      training = Dataset.standardize(rows, means, deviations)
      test = Dataset.standardize(@expanded_test, means, deviations)
      targets = @y_train.first(size)
      weights = Optimizers.newton(training, targets, @lambda).last[1]
      train_loss = Logistic.average_loss(weights, training, targets)
      test_loss = Logistic.average_loss(weights, test, @y_test)
      probabilities = Logistic.probabilities(weights, test)
      lines << "size #{size} train_loss #{real(train_loss, 6)} test_loss #{real(test_loss, 6)} test_accuracy #{ratio(correct(probabilities, @y_test), @m)} auc #{fraction(Metrics.auc(probabilities, @y_test))}"
    end
    lines
  end

  def bin_name(index)
    "#{index / 10}.#{index % 10}-#{(index + 1) / 10}.#{(index + 1) % 10}"
  end

  def calibration_lines(probabilities)
    counts = Array.new(10, 0)
    sums = Array.new(10, 0.0)
    positives = Array.new(10, 0)
    probabilities.each_with_index do |value, index|
      bin = [9, (value * 10).floor].min
      counts[bin] += 1
      sums[bin] += value
      positives[bin] += @y_test[index]
    end
    lines = ['calibration']
    ece = mce = statistic = 0.0
    groups = 0
    10.times do |bin|
      count = counts[bin]
      probability = count.zero? ? '-' : real(sums[bin] / count.to_f)
      lines << "bin #{bin_name(bin)} count #{count} mean_probability #{probability} positive_rate #{ratio(positives[bin], count)}"
      next if count.zero?

      groups += 1
      difference = positives[bin] - sums[bin]
      ece += difference.abs
      mce = [mce, (sums[bin] / count.to_f - positives[bin].to_f / count.to_f).abs].max
      statistic += difference * difference / (sums[bin] * (1.0 - sums[bin] / count.to_f))
    end
    lines << "ece #{real(ece / @m.to_f)} mce #{real(mce)} hosmer_lemeshow #{real(statistic)} groups #{groups}"
    lines
  end

  def binary_section(name)
    probabilities = @probabilities[name]
    weights = @weights[name]
    counts = Metrics.confusion(probabilities, @y_test, @settings[:threshold])
    tp, fp, tn, fn = counts.values_at(:tp, :fp, :tn, :fn)
    train_correct = correct(Logistic.probabilities(weights, @x_train), @y_train)
    brier = mean(probabilities.each_with_index.map { |value, index| (value - @y_test[index]) * (value - @y_test[index]) })
    loss = Logistic.average_loss(weights, @x_test, @y_test)
    points = Metrics.roc(probabilities, @y_test)
    previous = 0
    precision_sum = 0.0
    points.each do |_threshold, true_positive, false_positive|
      precision_sum += ((true_positive - previous) * true_positive).to_f / (true_positive + false_positive).to_f
      previous = true_positive
    end
    youden = points.max_by { |threshold, true_positive, false_positive| [true_positive * @negative - false_positive * @positive, threshold] }
    best_f1 = points.max_by { |threshold, true_positive, false_positive| [Rational(2 * true_positive, @positive + true_positive + false_positive), threshold] }
    c_fp, c_fn = @settings[:cost]
    cheapest = points.min_by { |threshold, true_positive, false_positive| [c_fp * false_positive + c_fn * (@positive - true_positive), -threshold] }
    lines = [
      "model #{name} lambda #{real(@lambda)}",
      "train correct #{train_correct}/#{@n} accuracy #{ratio(train_correct, @n)}",
      "test tp #{tp} fp #{fp} tn #{tn} fn #{fn}",
      "test accuracy #{ratio(tp + tn, @m)} precision #{ratio(tp, tp + fp)} recall #{ratio(tp, tp + fn)} specificity #{ratio(tn, tn + fp)} f1 #{ratio(2 * tp, 2 * tp + fp + fn)}",
      "log_loss #{real(loss, 6)} brier #{real(brier, 6)}",
      "auc #{fraction(Metrics.auc(probabilities, @y_test))} average_precision #{real(precision_sum / @positive.to_f)}"
    ]
    threshold, true_positive, false_positive = youden
    lines << "youden threshold #{real(threshold, 6)} tpr #{ratio(true_positive, @positive)} fpr #{ratio(false_positive, @negative)} j #{ratio(true_positive * @negative - false_positive * @positive, @positive * @negative)}"
    threshold, true_positive, false_positive = best_f1
    lines << "best_f1 threshold #{real(threshold, 6)} precision #{ratio(true_positive, true_positive + false_positive)} recall #{ratio(true_positive, @positive)} f1 #{ratio(2 * true_positive, @positive + true_positive + false_positive)}"
    threshold, true_positive, false_positive = cheapest
    cost = c_fp * false_positive + c_fn * (@positive - true_positive)
    lines << "min_cost threshold #{real(threshold, 6)} cost #{cost} fp #{false_positive} fn #{@positive - true_positive}"
    lines.concat(calibration_lines(probabilities))
    lines << 'gains'
    order = probabilities.each_index.sort_by { |index| [-probabilities[index], index] }
    (1..10).each do |decile|
      size = decile * @m / 10
      hits = order.first(size).count { |index| @y_test[index] == 1 }
      lines << "decile #{decile} rows #{size} positives #{hits} gain #{ratio(hits, @positive)} lift #{ratio(hits * @m, size * @positive)}"
    end
    @roc_lines << "#{name},inf,0.0000,0.0000,-"
    points.each do |value, true_positive, false_positive|
      @roc_lines << [name, real(value, 6), ratio(true_positive, @positive), ratio(false_positive, @negative), ratio(true_positive, true_positive + false_positive)].join(',')
    end
    lines
  end

  def comparison_section
    [%w[gd sgd], %w[gd newton], %w[sgd newton]].map do |first, second|
      equal = only_first = only_second = 0
      @m.times do |index|
        a = @predictions[first][index]
        b = @predictions[second][index]
        equal += 1 if a == b
        only_first += 1 if a == @y_test[index] && b != @y_test[index]
        only_second += 1 if b == @y_test[index] && a != @y_test[index]
      end
      difference = (only_first - only_second).abs - 1
      "agreement #{first} #{second} same #{equal}/#{@m} only_first #{only_first} only_second #{only_second} mcnemar #{ratio(difference * difference, only_first + only_second)}"
    end
  end

  def base_vector(values)
    Dataset.standardize([Dataset.expand(values, @tuples)], @means, @deviations)[0]
  end

  def slope(values, feature)
    result = 0.0
    @tuples.each_with_index do |tuple, index|
      count = tuple.count(feature)
      next if count.zero?

      removed = false
      product = 1.0
      tuple.each do |base|
        if base == feature && !removed
          removed = true
        else
          product *= values[base]
        end
      end
      result += @original_newton[index + 1] * (count * product)
    end
    result
  end

  def training_hl_lines
    probabilities = @influence[:rows].map { |row| row[:probability] }
    order = probabilities.each_index.sort_by { |index| [probabilities[index], index] }
    lines = []
    statistic = 0.0
    (1..10).each do |group|
      members = order[((group - 1) * @n / 10)...(group * @n / 10)]
      observed = members.count { |index| @y_train[index] == 1 }
      expected = total(members.map { |index| probabilities[index] })
      difference = observed - expected
      statistic += difference * difference / (expected * (1.0 - expected / members.length.to_f))
      lines << "group #{group} rows #{members.length} observed #{observed} expected #{real(expected)}"
    end
    ["hosmer_lemeshow_train groups 10 statistic #{real(statistic)}"] + lines
  end

  def bootstrap_line
    count, seed = @settings[:bootstrap]
    generator = Optimizers::Minstd.new(seed)
    aucs = Array.new(count) do
      selection = Array.new(@m) { generator.draw % @m }
      probabilities = selection.map { |index| @probabilities['newton'][index] }
      targets = selection.map { |index| @y_test[index] }
      Metrics.auc(probabilities, targets)
    end
    values = aucs.map { |numerator, denominator| numerator.to_f / denominator.to_f }
    average = mean(values)
    deviation = Math.sqrt(total(values.map { |value| (value - average) * (value - average) }) / (count - 1).to_f)
    ordered = aucs.sort_by { |numerator, denominator| Rational(numerator, denominator) }
    lower = ordered[count / 40]
    upper = ordered[count - count / 40 - 1]
    "bootstrap resamples #{count} seed #{seed} auc_mean #{real(average)} auc_sd #{real(deviation)} lower #{fraction(lower)} upper #{fraction(upper)}"
  end

  def diagnostics_section
    prevalence = @y_train.count(1).to_f / @n.to_f
    null_loss = -(prevalence * Math.log(prevalence) + (1.0 - prevalence) * Math.log(1.0 - prevalence))
    fit = @influence
    lines = [
      "diagnostics newton lambda #{real(@lambda)}",
      "fit null_loss #{real(null_loss, 6)} train_loss #{real(fit[:loss], 6)} mcfadden_r2 #{real(1.0 - fit[:loss] / null_loss)} deviance #{real(fit[:deviance])} edf #{real(fit[:edf])} aic #{real(fit[:aic])} bic #{real(fit[:bic])}"
    ]
    lines.concat(training_hl_lines)
    lines << 'newton_iterations'
    (1..10).each do |iteration|
      weights = @checkpoints['newton'][iteration - 1][1]
      gradient = Logistic.gradient(weights, @x_train, @y_train, @lambda)
      step = Optimizers.solve(Optimizers.cholesky(Logistic.hessian(weights, @x_train, @lambda)), gradient)
      decrease = total(gradient.each_index.map { |index| gradient[index] * step[index] }) / 2.0
      objective = Logistic.objective(weights, @x_train, @y_train, @lambda)
      lines << "iteration #{iteration} objective #{real(objective, 6)} gradient_norm #{real(length(gradient), 6)} step_norm #{real(length(step), 6)} predicted_decrease #{real(decrease, 6)}"
    end
    at_mean = Logistic.probability(Logistic.score(@weights['newton'], base_vector(@base_mean)))
    @names.each_with_index do |name, feature|
      average = mean(@training.each_index.map do |index|
        probability = fit[:rows][index][:probability]
        probability * (1.0 - probability) * slope(@training[index].values, feature)
      end)
      marginal_mean = at_mean * (1.0 - at_mean) * slope(@base_mean, feature)
      lines << "marginal #{name} average #{real(average)} at_mean #{real(marginal_mean)}"
    end
    (1..9).each do |cut|
      counts = Metrics.confusion(@probabilities['newton'], @y_test, cut.to_f / 10.0)
      tp, fp, tn, fn = counts.values_at(:tp, :fp, :tn, :fn)
      lines << "cut 0.#{cut} positive #{tp + fp} tp #{tp} fp #{fp} precision #{ratio(tp, tp + fp)} recall #{ratio(tp, tp + fn)} accuracy #{ratio(tp + tn, @m)}"
    end
    errors = (0...@m).select { |index| @predictions['newton'][index] != @y_test[index] }
    errors.sort_by! { |index| [-(@probabilities['newton'][index] - @settings[:threshold]).abs, index] }
    errors.first(5).each do |index|
      lines << "error #{@test[index].id} actual #{@y_test[index]} probability #{real(@probabilities['newton'][index], 6)}"
    end
    lines << bootstrap_line
    large = fit[:rows].count { |row| row[:residual].abs > 2.0 }
    lines << "influence effective_parameters #{real(fit[:edf])} large_residuals #{large}"
    order = (0...@n).sort_by { |index| [-fit[:rows][index][:cook], index] }
    order.first(5).each do |index|
      row = fit[:rows][index]
      lines << "cook #{@training[index].id} actual #{@y_train[index]} probability #{real(row[:probability])} leverage #{real(row[:leverage])} residual #{real(row[:residual])} distance #{real(row[:cook])}"
    end
    lines
  end

  def importance_section
    repetitions, seed = @settings[:permutation]
    generator = Optimizers::Minstd.new(seed)
    baseline_loss = Logistic.average_loss(@weights['newton'], @x_test, @y_test)
    baseline_auc = Metrics.auc(@probabilities['newton'], @y_test)
    baseline_correct = @m.times.count { |index| @soft_predictions[index] == @test[index].label }
    lines = ["importance repeats #{repetitions} seed #{seed}",
             "baseline log_loss #{real(baseline_loss, 6)} auc #{fraction(baseline_auc)} softmax_accuracy #{ratio(baseline_correct, @m)}"]
    @names.each_with_index do |name, feature|
      losses = 0.0
      auc_numerator = softmax_correct = 0
      repetitions.times do
        order = generator.shuffle!((0...@m).to_a)
        expanded = @test.each_with_index.map do |row, index|
          values = row.values.dup
          values[feature] = @test[order[index]].values[feature]
          Dataset.expand(values, @tuples)
        end
        vectors = Dataset.standardize(expanded, @means, @deviations)
        losses += Logistic.average_loss(@weights['newton'], vectors, @y_test)
        probabilities = Logistic.probabilities(@weights['newton'], vectors)
        auc_numerator += Metrics.auc(probabilities, @y_test)[0]
        vectors.each_with_index do |vector, index|
          prediction = Softmax.predict(Softmax.probabilities(@soft_weights, vector))
          softmax_correct += 1 if prediction == @test[index].label
        end
      end
      lines << "feature #{name} log_loss_increase #{real(losses / repetitions.to_f - baseline_loss, 6)} auc #{fraction([auc_numerator, repetitions * baseline_auc[1]])} softmax_accuracy #{ratio(softmax_correct, repetitions * @m)}"
    end
    lines
  end

  def profiles_section
    lines = ['profiles']
    @names.each_with_index do |name, feature|
      low, high = @training.map { |row| row.values[feature] }.minmax
      (0..4).each do |point|
        values = @base_mean.dup
        values[feature] = low + (high - low) * point / 4.0
        vector = base_vector(values)
        probability = Logistic.probability(Logistic.score(@weights['newton'], vector))
        softmax = Softmax.probabilities(@soft_weights, vector).map { |value| real(value) }.join(' ')
        lines << "profile #{name} value #{real(values[feature])} newton #{real(probability)} softmax #{softmax}"
      end
    end
    lines
  end

  def confidence_lines
    counts = Array.new(10, 0)
    sums = Array.new(10, 0.0)
    hits = Array.new(10, 0)
    @m.times do |index|
      prediction = @soft_predictions[index]
      confidence = @soft_probabilities[index][prediction]
      bin = [9, (confidence * 10).floor].min
      counts[bin] += 1
      sums[bin] += confidence
      hits[bin] += 1 if prediction == @test[index].label
    end
    lines = ['confidence']
    error = 0.0
    10.times do |bin|
      average = counts[bin].zero? ? '-' : real(sums[bin] / counts[bin].to_f)
      lines << "bin #{bin_name(bin)} count #{counts[bin]} mean_confidence #{average} accuracy #{ratio(hits[bin], counts[bin])}"
      error += (sums[bin] - hits[bin]).abs unless counts[bin].zero?
    end
    lines << "ece #{real(error / @m.to_f)}"
    lines
  end

  def softmax_section
    table = Array.new(@classes) { Array.new(@classes, 0) }
    @m.times { |index| table[@test[index].label][@soft_predictions[index]] += 1 }
    row_counts = table.map(&:sum)
    column_counts = Array.new(@classes) { |klass| table.sum { |row| row[klass] } }
    diagonal = (0...@classes).sum { |klass| table[klass][klass] }
    cross = (0...@classes).sum { |klass| row_counts[klass] * column_counts[klass] }
    lines = ["softmax classes #{@classes} lambda #{real(@settings[:softmax][2])} iterations #{@settings[:softmax][1]}", 'confusion']
    table.each { |row| lines << row.join(' ') }
    @classes.times do |klass|
      targets = @test.map { |row| row.label == klass ? 1 : 0 }
      probabilities = @soft_probabilities.map { |row| row[klass] }
      lines << "class #{klass} precision #{ratio(table[klass][klass], column_counts[klass])} recall #{ratio(table[klass][klass], row_counts[klass])} f1 #{ratio(2 * table[klass][klass], column_counts[klass] + row_counts[klass])} auc #{fraction(Metrics.auc(probabilities, targets))}"
    end
    lines << "accuracy #{ratio(diagonal, @m)} kappa #{ratio(@m * diagonal - cross, @m * @m - cross)}"
    brier = 0.0
    @m.times do |index|
      row_error = 0.0
      @classes.times do |klass|
        difference = @soft_probabilities[index][klass] - (@test[index].label == klass ? 1.0 : 0.0)
        row_error += difference * difference
      end
      brier += row_error
    end
    log_loss = Softmax.average_loss(@soft_weights, @x_test, @test.map(&:label))
    lines << "log_loss #{real(log_loss, 6)} brier #{real(brier / @m.to_f, 6)}"
    binary = @soft_probabilities.map { |row| row[@settings[:positive]] }
    binary_loss = mean(binary.each_with_index.map do |probability, index|
      -Math.log(@y_test[index] == 1 ? probability : 1.0 - probability)
    end)
    predictions = binary.map { |value| value >= @settings[:threshold] ? 1 : 0 }
    agreement = @m.times.count { |index| predictions[index] == @predictions['newton'][index] }
    lines << "binary_view positive_class #{@settings[:positive]} auc #{fraction(Metrics.auc(binary, @y_test))} log_loss #{real(binary_loss, 6)} accuracy #{ratio(correct(binary, @y_test), @m)} agreement_with_newton #{agreement}/#{@m}"
    lines.concat(confidence_lines)
    lines
  end

  def one_vs_rest_section
    lambda = @settings[:softmax][2]
    lines = ["one_vs_rest lambda #{real(lambda)} newton_iterations 10"]
    probabilities = Array.new(@classes) do |klass|
      targets = @labels.map { |label| label == klass ? 1 : 0 }
      weights = Optimizers.newton(@x_train, targets, lambda).last[1]
      values = Logistic.probabilities(weights, @x_test)
      test_targets = @test.map { |row| row.label == klass ? 1 : 0 }
      objective = Logistic.objective(weights, @x_train, targets, lambda)
      lines << "class #{klass} objective #{real(objective, 6)} auc #{fraction(Metrics.auc(values, test_targets))}"
      values
    end
    number_correct = agreement = 0
    @m.times do |index|
      prediction = (0...@classes).max_by { |klass| [probabilities[klass][index], -klass] }
      number_correct += 1 if prediction == @test[index].label
      agreement += 1 if prediction == @soft_predictions[index]
    end
    lines << "accuracy #{ratio(number_correct, @m)} agreement_with_softmax #{agreement}/#{@m}"
    lines
  end

  def maps_section
    width, height = @settings[:map]
    low_x, high_x = @training.map { |row| row.values[0] }.minmax
    low_y, high_y = @training.map { |row| row.values[1] }.minmax
    class_rows = []
    probability_rows = []
    counts = Array.new(@classes, 0)
    height.times do |row|
      classes = []
      probabilities = []
      width.times do |column|
        values = @base_mean.dup
        values[0] = low_x + (column + 0.5) * (high_x - low_x) / width.to_f
        values[1] = high_y - (row + 0.5) * (high_y - low_y) / height.to_f
        vector = base_vector(values)
        klass = Softmax.predict(Softmax.probabilities(@soft_weights, vector))
        counts[klass] += 1
        classes << klass.to_s
        probability = Logistic.probability(Logistic.score(@weights['newton'], vector))
        probabilities << [9, (probability * 10).floor].min.to_s
      end
      class_rows << classes.join
      probability_rows << probabilities.join
    end
    ["map #{@names[0]} #{@names[1]} width #{width} height #{height}", 'softmax_classes'] +
      class_rows + ["cells #{counts.join(' ')}", 'newton_probability'] + probability_rows
  end

  def run
    train_models
    @roc_lines = ['model,threshold,tpr,fpr,precision']
    parts = [data_section, validation_section, path_section, degree_section, learning_section]
    MODELS.each { |name| parts << binary_section(name) }
    parts << comparison_section
    parts << diagnostics_section
    parts << importance_section
    parts << profiles_section
    parts << softmax_section
    parts << one_vs_rest_section
    parts << maps_section
    files = {
      'weights.txt' => weights_lines,
      'loss_trace.csv' => trace_lines,
      'predictions.csv' => prediction_lines,
      'evaluation.txt' => separate(parts),
      'roc.csv' => @roc_lines
    }
    FileUtils.mkdir_p('output')
    files.each { |name, lines| File.binwrite("output/#{name}", lines.join("\n") + "\n") }
  end
end

LogisticAnalysis.new.run
