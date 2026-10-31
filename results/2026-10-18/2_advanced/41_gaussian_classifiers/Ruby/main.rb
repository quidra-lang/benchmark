require_relative 'dataset'
require_relative 'linalg'
require_relative 'gaussian_models'
require_relative 'evaluation'
require_relative 'plot'

class Analysis
  include Linalg
  include GaussianModels
  include Evaluation
  include Plot

  MODEL_NAMES = GaussianModels::MODEL_NAMES
  CrossValidation = Data.define(:predictions, :fold_correct, :correct)

  def initialize(data)
    @data = data
    @params, @features, @classes = data.params, data.features, data.classes
    @train, @test = data.train, data.test
    @n, @m = @train.length, @test.length
    @d, @class_count = @features.length, @classes.length
    @all_features = (0...@d).to_a.freeze
    @train_actual = @train.map(&:class_index)
    @test_actual = @test.map(&:class_index)
    @upper_letters = @classes.map { |name| name[0].upcase }
    @lower_letters = @classes.map { |name| name[0] }
    @folds = @train.map { |row| row.id % @params[:folds] }
    @fold_sizes = Array.new(@params[:folds]) { |fold| @folds.count(fold) }
    @cv_cache = {}
    @main_models = MODEL_NAMES.map { |name| fit(name) }
    @results = @main_models.map { |model| @test.map { |row| model.infer(row.values, @data.costs) } }
    @predictions = @results.map { |results| results.map(&:predicted) }
  end

  def fit(name, features: @all_features, rows: @train, prior_mode: @params[:prior],
          epsilon: @params[:epsilon], gamma: @params[:gamma])
    GaussianModels.train(rows, features, @class_count, name, prior_mode, epsilon, gamma)
  end

  def cross_validate(name, features, epsilon: @params[:epsilon], gamma: @params[:gamma])
    features = features.dup.freeze
    key = [name, features, epsilon, gamma]
    return @cv_cache[key] if @cv_cache.key?(key)

    predictions = Array.new(@n)
    fold_correct = Array.new(@params[:folds]) do |fold|
      retained = @train.each_with_index.filter_map { |row, i| row if @folds[i] != fold }
      model = fit(name, features:, rows: retained, epsilon:, gamma:)
      correct = 0
      @train.each_with_index do |row, i|
        next unless @folds[i] == fold

        predictions[i] = model.predict(row.values)
        correct += 1 if predictions[i] == row.class_index
      end
      correct
    end
    @cv_cache[key] = CrossValidation.new(predictions, fold_correct, fold_correct.sum)
  end

  def confusion_lines(matrix)
    @classes.zip(matrix).map { |name, counts| "confusion #{name} #{counts.join(' ')}" }
  end

  def comparison_lines(title, names, predictions, actual)
    lines = [title]
    (0...names.length).to_a.combination(2) do |a, b|
      b01, b10, chi2, significant = mcnemar(actual, predictions[a], predictions[b])
      lines << "#{names[a]} #{names[b]} b01 #{b01} b10 #{b10} chi2 #{real(chi2)} " \
               "significant #{significant ? 'yes' : 'no'}"
    end
    lines
  end

  def point_grid(points, actual, letters, limits, size)
    xmin, xmax, ymin, ymax = limits
    width, height = size
    grid = Array.new(height) { Array.new(width, ' ') }
    points.zip(actual).each do |(x, y), class_index|
      column = cell(x, xmin, xmax, width)
      row = height - 1 - cell(y, ymin, ymax, height)
      letter = letters[class_index]
      previous = grid[row][column]
      grid[row][column] = previous == ' ' || previous == letter ? letter : '*'
    end
    grid
  end

  def nearest_centroid_correct(points, actual, centroids, dimensions)
    points.zip(actual).count do |point, expected|
      distances = centroids.map do |centroid|
        difference = point[0] - centroid[0]
        distance = difference * difference
        if dimensions == 2
          difference = point[1] - centroid[1]
          distance += difference * difference
        end
        distance
      end
      argmin(distances) == expected
    end
  end

  def model_sections
    nb, lda, qda = @main_models
    statistics = nb.statistics
    lines = ["features #{@features.join(' ')}", "classes #{@classes.join(' ')}",
             "prior_mode #{@params[:prior]}"]
    @classes.each_with_index do |name, k|
      lines << "class #{name} letter #{@upper_letters[k]} count #{statistics.counts[k]} " \
               "prior #{real(nb.priors[k])} mean #{reals(statistics.means[k])}"
    end
    sections = [lines]
    lines = ['model NB',
             "smoothing epsilon #{real(nb.epsilon)} max_variance #{real(nb.max_variance)} " \
             "added #{real(nb.added_variance)}"]
    @classes.each_with_index do |name, k|
      diagonal = Array.new(@d) { |j| nb.covariances[k][j][j] }
      lines << "class #{name} variance #{reals(diagonal)} log_det #{real(nb.log_determinants[k])}"
    end
    sections << lines
    lower = lda.factors.first
    lines = ['model LDA', "log_det #{real(lda.log_determinants.first)}"]
    lines.concat(lda.covariances.first.map { |row| '  ' + reals(row) })
    @classes.each_with_index do |name, k|
      coefficients = backward(lower, forward(lower, lda.means[k]))
      intercept = Math.log(lda.priors[k]) - dot(lda.means[k], coefficients) / 2
      lines << "class #{name} intercept #{real(intercept)} coef #{reals(coefficients)}"
    end
    sections << lines
    lines = ["model QDA gamma #{real(qda.gamma)}"]
    @classes.each_with_index do |name, k|
      eigenvalues, = jacobi(qda.covariances[k])
      eigenvalues.sort!.reverse!
      condition = eigenvalues.first / eigenvalues.last
      lines << "class #{name} log_det #{real(qda.log_determinants[k])} " \
               "eigenvalues #{reals(eigenvalues)} condition #{real(condition)}"
      lines.concat(qda.covariances[k].map { |row| '  ' + reals(row) })
    end
    sections << lines
    lines = ['separation']
    (0...@class_count).to_a.combination(2) do |a, b|
      difference = Array.new(@d) { |j| statistics.means[a][j] - statistics.means[b][j] }
      mahalanobis = Math.sqrt(quadratic_form(lower, difference))
      average = Array.new(@d) do |i|
        Array.new(@d) { |j| (qda.covariances[a][i][j] + qda.covariances[b][i][j]) / 2 }
      end
      average_lower = cholesky(average)
      bhattacharyya = quadratic_form(average_lower, difference) / 8 +
                      (log_determinant(average_lower) -
                       (qda.log_determinants[a] + qda.log_determinants[b]) / 2) / 2
      lines << "#{@classes[a]} #{@classes[b]} mahalanobis #{real(mahalanobis)} " \
               "bhattacharyya #{real(bhattacharyya)}"
    end
    sections << lines
    outliers = @train.each_with_index.filter_map do |row, i|
      distance = qda.distances(row.values)[row.class_index]
      [distance, i, row] if distance > @params[:outlier_threshold]
    end
    outliers.sort_by! { |distance, i, _| [-distance, i] }
    lines = ["outliers threshold #{real(@params[:outlier_threshold])}"]
    outliers.each { |distance, _, row| lines << "#{row.id} #{row.label} q #{real(distance)}" }
    lines << "count #{outliers.length}"
    sections << lines
    sections
  end

  def prediction_lines
    lines = ['id,model,actual,predicted,decision,' + @classes.join(',')]
    @test.each_with_index do |row, i|
      MODEL_NAMES.each_with_index do |name, k|
        result = @results[k][i]
        fields = [row.id, name, row.label, @classes[result.predicted], @classes[result.decision]]
        lines << (fields + result.posterior.map { |probability| real(probability) }).join(',')
      end
    end
    lines
  end

  def model_evaluation(model_index)
    results = @results[model_index]
    metrics = measures(@test_actual, @predictions[model_index], @class_count)
    lines = ["model #{MODEL_NAMES[model_index]}", *confusion_lines(metrics[:matrix])]
    %i[accuracy balanced_accuracy kappa].each { |key| lines << "#{key} #{fraction_text(metrics[key])}" }
    @classes.each_with_index do |name, k|
      lines << "class #{name} support #{metrics[:support][k]} recall #{fraction_text(metrics[:recall][k])} " \
               "precision #{fraction_text(metrics[:precision][k])} f1 #{fraction_text(metrics[:f1][k])}"
    end
    log_loss = -total(@test.zip(results).map { |row, result| result.log_posterior[row.class_index] }) / @m
    lines << "macro_f1 #{real(metrics[:macro_f1])}"
    lines << "log_loss #{real(log_loss)}"
    errors = @test.zip(results).select { |row, result| result.predicted != row.class_index }
    lines << "errors #{errors.length}"
    errors.each do |row, result|
      lines << "error #{row.id} actual #{row.label} predicted #{@classes[result.predicted]} " \
               "confidence #{real(result.confidence)}"
    end
    edges = [0.0, *@params[:calibration_edges], 1.0]
    calibration_error = 0.0
    edges.each_cons(2).with_index do |(low, high), bin|
      last_bin = bin == edges.length - 2
      indices = results.each_index.select do |i|
        results[i].confidence >= low &&
          (results[i].confidence < high || (last_bin && results[i].confidence == high))
      end
      count = indices.length
      confidence_sum = total(indices.map { |i| results[i].confidence })
      correct = indices.count { |i| results[i].predicted == @test_actual[i] }
      confidence_text = count.zero? ? '-' : real(confidence_sum / count)
      lines << "bin #{real(low)} #{real(high)} count #{count} confidence #{confidence_text} " \
               "accuracy #{ratio_text(correct, count)}"
      calibration_error += (correct - confidence_sum).abs
    end
    lines << "ece #{real(calibration_error / @m)}"
    @params[:reject_thresholds].each do |threshold|
      indices = results.each_index.select { |i| results[i].confidence >= threshold }
      count = indices.length
      correct = indices.count { |i| results[i].predicted == @test_actual[i] }
      lines << "reject #{real(threshold)} accepted #{count} coverage #{ratio_text(count, @m)} " \
               "accuracy #{ratio_text(correct, count)}"
    end
    lines
  end

  def ensemble_predictions
    Array.new(@m) do |i|
      posterior = Array.new(@class_count) { |k| total(@results.map { |results| results[i].posterior[k] }) / 3 }
      argmax(posterior)
    end
  end

  def cost_lines
    lines = ['costs']
    MODEL_NAMES.zip(@results).each do |name, results|
      argmax_total = total(@test.zip(results).map { |row, result| @data.costs[row.class_index][result.predicted] })
      decision_total = total(@test.zip(results).map { |row, result| @data.costs[row.class_index][result.decision] })
      changed = results.count { |result| result.predicted != result.decision }
      correct = @test.zip(results).count { |row, result| row.class_index == result.decision }
      lines << "#{name} argmax_total #{real(argmax_total)} decision_total #{real(decision_total)} " \
               "changed #{changed} decision_accuracy #{ratio_text(correct, @m)}"
    end
    lines
  end

  def novelty_lines
    novel = @test.each_with_index.filter_map do |row, i|
      distances = @main_models[2].distances(row.values)
      nearest = argmin(distances)
      distance = distances[nearest]
      [distance, i, row.id, nearest] if distance > @params[:outlier_threshold]
    end
    novel.sort_by! { |distance, i, _, _| [-distance, i] }
    lines = ["novelty threshold #{real(@params[:outlier_threshold])}"]
    novel.each do |distance, _, id, nearest|
      lines << "#{id} nearest #{@classes[nearest]} q #{real(distance)}"
    end
    lines << "count #{novel.length}"
    lines
  end

  def bootstrap_lines
    count = @params[:bootstrap_count]
    generator = RandomGenerator.new(@params[:seed])
    resamples = Array.new(3) { [] }
    count.times do
      correct = Array.new(3, 0)
      @m.times do
        i = generator.draw % @m
        3.times { |model| correct[model] += 1 if @predictions[model][i] == @test_actual[i] }
      end
      3.times { |model| resamples[model] << correct[model] }
    end
    lines = ["bootstrap resamples #{count} seed #{@params[:seed]}"]
    offset = count / 40
    MODEL_NAMES.zip(resamples).each do |name, counts|
      ordered = counts.sort
      mean = counts.sum.fdiv(count) / @m
      lines << "#{name} mean #{real(mean)} interval #{ratio_text(ordered[offset], @m)} " \
               "#{ratio_text(ordered[-offset - 1], @m)}"
    end
    (0...3).to_a.combination(2) do |a, b|
      wins = resamples[a].zip(resamples[b]).count { |left, right| left > right }
      ties = resamples[a].zip(resamples[b]).count { |left, right| left == right }
      losses = count - wins - ties
      lines << "#{MODEL_NAMES[a]} #{MODEL_NAMES[b]} wins #{wins} ties #{ties} losses #{losses}"
    end
    lines
  end

  def prior_lines
    alternative = @params[:prior] == 'empirical' ? 'uniform' : 'empirical'
    lines = ["prior_sensitivity alternative #{alternative}"]
    MODEL_NAMES.each_with_index do |name, k|
      model = fit(name, prior_mode: alternative)
      predictions = @test.map { |row| model.predict(row.values) }
      metrics = measures(@test_actual, predictions, @class_count)
      changed = predictions.zip(@predictions[k]).count { |a, b| a != b }
      lines << "#{name} accuracy #{fraction_text(metrics[:accuracy])} " \
               "balanced_accuracy #{fraction_text(metrics[:balanced_accuracy])} changed #{changed}"
    end
    lines
  end

  def learning_curve_lines
    lines = ['learning_curve']
    @params[:curve].each do |size|
      taken = Array.new(@class_count, 0)
      rows = @train.select do |row|
        next false unless taken[row.class_index] < size

        taken[row.class_index] += 1
        true
      end
      fields = ["size #{size} rows #{rows.length}"]
      MODEL_NAMES.each do |name|
        model = fit(name, rows:)
        correct = @test.count { |row| model.predict(row.values) == row.class_index }
        fields << "#{name} #{ratio_text(correct, @m)}"
      end
      lines << fields.join(' ')
    end
    lines
  end

  def subset_lines
    lines = ["cross_validation folds #{@params[:folds]}", "fold_sizes #{@fold_sizes.join(' ')}"]
    best_key = nil
    best = nil
    @params[:subsets].each_with_index do |(subset_name, features), subset_index|
      names = features.map { |j| @features[j] }.join(' ')
      lines << "subset #{subset_name} features #{names}"
      MODEL_NAMES.each_with_index do |name, model_index|
        result = cross_validate(name, features)
        lines << "  #{name} fold_correct #{result.fold_correct.join(' ')} correct #{result.correct} " \
                 "accuracy #{ratio_text(result.correct, @n)}"
        key = [-result.correct, features.length, subset_index, model_index]
        if best_key.nil? || (key <=> best_key).negative?
          best_key = key
          best = [subset_name, features, name, result.correct]
        end
      end
    end
    subset_name, features, name, correct = best
    lines << "best subset #{subset_name} model #{name} correct #{correct} accuracy #{ratio_text(correct, @n)}"
    model = fit(name, features:)
    correct = @test.count { |row| model.predict(row.values) == row.class_index }
    lines << "refit_test correct #{correct} accuracy #{ratio_text(correct, @m)}"
    lines
  end

  def leave_one_out_lines
    lines = ['leave_one_out']
    MODEL_NAMES.each do |name|
      correct = 0
      @train.each_with_index do |row, i|
        rows = @train.first(i) + @train.drop(i + 1)
        model = fit(name, rows:)
        correct += 1 if model.predict(row.values) == row.class_index
      end
      lines << "#{name} correct #{correct} accuracy #{ratio_text(correct, @n)}"
    end
    lines
  end

  def forward_selection_sections
    MODEL_NAMES.map do |name|
      lines = ["forward_selection model #{name}"]
      selected = []
      best_step, best_correct = 0, -1
      (1..@d).each do |step|
        added, step_correct = nil, -1
        @all_features.each do |feature|
          next if selected.include?(feature)

          result = cross_validate(name, selected + [feature])
          added, step_correct = feature, result.correct if result.correct > step_correct
        end
        selected << added
        lines << "step #{step} add #{@features[added]} correct #{step_correct} " \
                 "accuracy #{ratio_text(step_correct, @n)}"
        best_step, best_correct = step, step_correct if step_correct > best_correct
      end
      names = selected.first(best_step).map { |feature| @features[feature] }.join(' ')
      lines << "best_step #{best_step} features #{names}"
      lines
    end
  end

  def tuning_lines(name, parameter, values, title)
    lines = [title]
    best_value, best_correct = nil, -1
    values.each do |value|
      result = cross_validate(name, @all_features, **{ parameter => value })
      lines << "value #{real(value)} correct #{result.correct} accuracy #{ratio_text(result.correct, @n)}"
      best_value, best_correct = value, result.correct if result.correct >= best_correct
    end
    model = fit(name, **{ parameter => best_value })
    correct = @test.count { |row| model.predict(row.values) == row.class_index }
    lines << "best #{real(best_value)} test correct #{correct} accuracy #{ratio_text(correct, @m)}"
    lines
  end

  def evaluation_sections
    sections = [["test rows #{@m}"]]
    3.times { |i| sections << model_evaluation(i) }
    ensemble = ensemble_predictions
    metrics = measures(@test_actual, ensemble, @class_count)
    sections << ['ensemble soft_vote',
                 "accuracy #{fraction_text(metrics[:accuracy])} " \
                 "balanced_accuracy #{fraction_text(metrics[:balanced_accuracy])} kappa #{fraction_text(metrics[:kappa])}"]
    sections << comparison_lines('mcnemar test', MODEL_NAMES + ['ENSEMBLE'], @predictions + [ensemble], @test_actual)
    sections.concat([cost_lines, novelty_lines, bootstrap_lines, prior_lines, learning_curve_lines, subset_lines])
    cvs = MODEL_NAMES.map { |name| cross_validate(name, @all_features) }
    sections << comparison_lines('mcnemar cross_validation', MODEL_NAMES, cvs.map(&:predictions), @train_actual)
    MODEL_NAMES.zip(cvs).each do |name, result|
      metrics = measures(@train_actual, result.predictions, @class_count)
      lines = ["cv_confusion model #{name}", *confusion_lines(metrics[:matrix])]
      lines << "balanced_accuracy #{fraction_text(metrics[:balanced_accuracy])} kappa #{fraction_text(metrics[:kappa])}"
      sections << lines
    end
    sections << leave_one_out_lines
    sections.concat(forward_selection_sections)
    sections << tuning_lines('NB', :epsilon, @params[:smoothing_grid], 'nb_smoothing_path')
    sections << tuning_lines('QDA', :gamma, @params[:gamma_grid], 'qda_gamma_path')
    sections
  end

  def boundary_sections
    width, height = @params[:map_size]
    @params[:pairs].map do |fx, fy|
      xmin, xmax = @train.map { |row| row.values[fx] }.minmax
      ymin, ymax = @train.map { |row| row.values[fy] }.minmax
      dx = (xmax - xmin) / (width - 1)
      dy = (ymax - ymin) / (height - 1)
      grid_points = Array.new(height) do |row|
        Array.new(width) { |column| [xmin + column * dx, ymax - row * dy] }
      end
      lines = ["pair #{@features[fx]} #{@features[fy]}",
               "x #{@features[fx]} #{real(xmin)} #{real(xmax)} " \
               "y #{@features[fy]} #{real(ymin)} #{real(ymax)} grid #{width}x#{height}"]
      all_grids = MODEL_NAMES.map do |name|
        model = fit(name, features: [fx, fy])
        correct = @train.count { |row| model.predict(row.values) == row.class_index }
        cv = cross_validate(name, [fx, fy])
        lines << "model #{name} train_accuracy #{ratio_text(correct, @n)} cv_accuracy #{ratio_text(cv.correct, @n)}"
        results = grid_points.map { |row| row.map { |point| model.infer_vector(point) } }
        letter_grid = results.map { |row| row.map { |result| @upper_letters[result.predicted] } }
        lines.concat(frame(letter_grid))
        counts = Array.new(@class_count, 0)
        results.each { |row| row.each { |result| counts[result.predicted] += 1 } }
        cells = @upper_letters.zip(counts).map { |letter, count| "#{letter} #{count}" }.join(' ')
        lines << "cells #{cells}"
        results
      end
      agreement = Array.new(height) { Array.new(width) }
      uncertainty = Array.new(height) { Array.new(width) }
      disagreements = 0
      height.times do |row|
        width.times do |column|
          distinct = all_grids.map { |grid| grid[row][column].predicted }.uniq.length
          agreement[row][column] = distinct == 1 ? '.' : distinct.to_s
          disagreements += 1 if distinct != 1
          confidence = all_grids[2][row][column].confidence
          uncertainty_value = (1 - confidence) / (1 - 1.0 / @class_count)
          level = [9, (10 * uncertainty_value).floor].min
          uncertainty[row][column] = ' .:-=+*#%@'[level]
        end
      end
      lines << 'agreement'
      lines.concat(frame(agreement))
      lines << "disagreement_cells #{disagreements}"
      lines << 'uncertainty QDA'
      lines.concat(frame(uncertainty))
      points = @train.map { |row| [row.values[fx], row.values[fy]] }
      grid = point_grid(points, @train_actual, @lower_letters, [xmin, xmax, ymin, ymax], @params[:map_size])
      lines << 'points'
      lines.concat(frame(grid))
      lines
    end
  end

  def projection_sections
    statistics = @main_models.first.statistics
    center = statistics.center
    within = zeros(@d)
    between = zeros(@d)
    @d.times do |a|
      @d.times do |b|
        within[a][b] = total(statistics.scatter.map { |scatter| scatter[a][b] })
        between[a][b] = total(Array.new(@class_count) do |k|
          statistics.counts[k] * (statistics.means[k][a] - center[a]) * (statistics.means[k][b] - center[b])
        end)
      end
    end
    f_values = Array.new(@d) do |j|
      (between[j][j] / (@class_count - 1)) / (within[j][j] / (@n - @class_count))
    end
    feature_order = @all_features.sort_by { |j| [-f_values[j], j] }
    univariate = ['univariate']
    feature_order.each_with_index do |j, i|
      univariate << "rank #{i + 1} #{@features[j]} f #{real(f_values[j])} " \
                    "between #{real(between[j][j])} within #{real(within[j][j])}"
    end
    lower = cholesky(within)
    transformed = zeros(@d)
    @d.times do |j|
      column = forward(lower, Array.new(@d) { |a| between[a][j] })
      @d.times { |a| transformed[a][j] = column[a] }
    end
    whitened = zeros(@d)
    @d.times do |i|
      column = forward(lower, transformed[i])
      @d.times { |a| whitened[a][i] = column[a] }
    end
    symmetric = Array.new(@d) do |a|
      Array.new(@d) { |b| (whitened[a][b] + whitened[b][a]) / 2 }
    end
    eigenvalues, eigenvectors, sweeps = jacobi(symmetric)
    eigenvalue_order = @all_features.sort_by { |j| [-eigenvalues[j], j] }
    eigenvalue_sum = total(eigenvalues)
    directions = eigenvalue_order.first(2).map do |index|
      eigenvector = Array.new(@d) { |j| eigenvectors[j][index] }
      direction = backward(lower, eigenvector)
      norm = Math.sqrt(dot(direction, direction))
      direction.map! { |value| value / norm }
      pivot = argmax(direction.map(&:abs))
      direction.map! { |value| -value } if direction[pivot] < 0
      direction
    end
    project = lambda do |vector|
      directions.map do |direction|
        total(Array.new(@d) { |j| direction[j] * (vector[j] - center[j]) })
      end
    end
    train_points = @train.map { |row| project.call(row.values) }
    test_points = @test.map { |row| project.call(row.values) }
    centroids = statistics.means.map { |mean| project.call(mean) }
    fisher = ["fisher features #{@features.join(' ')}", "center #{reals(center)}", "sweeps #{sweeps}",
              'eigenvalues ' + reals(eigenvalue_order.map { |j| eigenvalues[j] }),
              'ratios ' + reals(eigenvalue_order.map { |j| eigenvalues[j] / eigenvalue_sum })]
    pooled = @main_models[1].covariances.first
    directions.each_with_index do |direction, i|
      standardized = Array.new(@d) { |j| direction[j] * Math.sqrt(pooled[j][j]) }
      fisher << "direction #{i + 1} #{reals(direction)}"
      fisher << "standardized #{i + 1} #{reals(standardized)}"
    end
    @classes.each_with_index do |name, k|
      indices = @train_actual.each_index.select { |i| @train_actual[i] == k }
      spread = Array.new(2) do |t|
        squared = total(indices.map do |i|
          (train_points[i][t] - centroids[k][t]) * (train_points[i][t] - centroids[k][t])
        end)
        Math.sqrt(squared / statistics.counts[k])
      end
      fisher << "centroid #{name} #{reals(centroids[k])} spread #{reals(spread)}"
    end
    [1, 2].each do |dimensions|
      train_correct = nearest_centroid_correct(train_points, @train_actual, centroids, dimensions)
      test_correct = nearest_centroid_correct(test_points, @test_actual, centroids, dimensions)
      fisher << "nearest_centroid dims #{dimensions} train #{ratio_text(train_correct, @n)} " \
                "test #{ratio_text(test_correct, @m)}"
    end
    xmin, xmax = train_points.map(&:first).minmax
    ymin, ymax = train_points.map(&:last).minmax
    width, height = @params[:plot_size]
    grid = point_grid(train_points, @train_actual, @lower_letters, [xmin, xmax, ymin, ymax], @params[:plot_size])
    centroids.each_with_index do |(x, y), k|
      column = cell(x, xmin, xmax, width)
      row = height - 1 - cell(y, ymin, ymax, height)
      grid[row][column] = @upper_letters[k]
    end
    scatter = ["plot x #{real(xmin)} #{real(xmax)} y #{real(ymin)} #{real(ymax)} size #{width}x#{height}", *frame(grid)]
    [univariate, fisher, scatter]
  end

  def write_outputs
    write_lines('output/models.txt', join_sections(model_sections))
    write_lines('output/predictions.csv', prediction_lines)
    write_lines('output/evaluation.txt', join_sections(evaluation_sections))
    write_lines('output/boundaries.txt', join_sections(boundary_sections))
    write_lines('output/projection.txt', join_sections(projection_sections))
  end
end

Analysis.new(Dataset.read_inputs).write_outputs if $PROGRAM_NAME == __FILE__
