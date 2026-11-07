# frozen_string_literal: true

require 'set'
require_relative 'dataset'
require_relative 'scaling'
require_relative 'neighbors'
require_relative 'validation'
require_relative 'report'

class KNNStudy
  def initialize
    @features, @training, @testing, @settings = Dataset.read
    @used_features = @features.each_index.to_a
    @labels = @training.map(&:label).uniq.sort
    @labelled = @testing.reject { |row| row.label.nil? }
    @targets = @testing.reject { |row| row.target.nil? }
    @grid = @settings[:k_values].product(@settings[:metrics], @settings[:weightings], @settings[:scalings])
                     .each_with_index.map do |(k, metric, weighting, scaling), index|
      { k: k, metric: metric, weighting: weighting, scaling: scaling, index: index }
    end
    @folds = Validation.folds(@training, @settings[:folds])
  end

  def model_text(model)
    %i[k metric weighting scaling].map { |key| "#{key}=#{model[key]}" }.join(' ')
  end

  def label_counts(rows)
    counts = rows.map(&:label).tally
    @labels.map { |label| "#{label} #{counts.fetch(label, 0)}" }.join(' ')
  end

  def correct(rows, predictions)
    rows.count { |row| row.label == predictions.fetch(row.id).label }
  end

  def predict_rows(rows, predictor, model)
    rows.to_h { |row| [row.id, predictor.predict(row, model)] }
  end

  def cross_validate(rows, models = @grid, features = @used_features)
    results = models.map { |model| { model: model, predictions: {} } }
    Validation.folds(rows, @settings[:folds]).each do |validation|
      ids = validation.map(&:id).to_set
      reference = rows.reject { |row| ids.include?(row.id) }
      predictor = Validation::Predictor.new(reference, features)
      results.each do |result|
        result[:predictions].merge!(predict_rows(validation, predictor, result[:model]))
      end
    end
    results.each do |result|
      result[:correct] = correct(rows, result[:predictions])
      result[:rmse] = Validation.errors(rows, result[:predictions])[:rmse]
    end
    results
  end

  def accuracy_rank(results)
    results.sort_by { |result| [-result[:correct], result[:model][:index]] }
  end

  def rmse_rank(results)
    results.sort_by { |result| [Report.rounded(result[:rmse]), result[:model][:index]] }
  end

  def selection_text(result, kind)
    model = model_text(result[:model])
    ratio = Report.ratio(result[:correct], @training.length)
    rmse = Report.real(result[:rmse])
    kind == :classifier ? "#{model} correct #{ratio} rmse #{rmse}" : "#{model} rmse #{rmse} correct #{ratio}"
  end

  def evaluation(rows, predictions)
    indices = @labels.each_with_index.to_h
    matrix = Array.new(@labels.length) { Array.new(@labels.length, 0) }
    rows.each { |row| matrix[indices[row.label]][indices[predictions.fetch(row.id).label]] += 1 }
    lines = ['true\\predicted ' + @labels.join(' ')]
    @labels.each_with_index { |label, index| lines << label + ' ' + matrix[index].join(' ') }
    averages = { precision: [], recall: [], f1: [] }
    @labels.each_with_index do |label, index|
      true_positive = matrix[index][index]
      predicted = matrix.sum { |row| row[index] }
      actual = matrix[index].sum
      metrics = { precision: [true_positive, predicted], recall: [true_positive, actual],
                  f1: [2 * true_positive, predicted + actual] }
      details = metrics.map do |name, (numerator, denominator)|
        averages[name] << numerator.to_f / denominator.to_f unless denominator.zero?
        "#{name} #{Report.reduced(numerator, denominator)}"
      end
      lines << "class #{label} #{details.join(' ')} support #{actual}"
    end
    macro = averages.map do |name, values|
      average = values.empty? ? nil : values.reduce(0.0, :+) / values.length.to_f
      "#{name} #{Report.real(average)}"
    end
    lines << 'macro ' + macro.join(' ')
    lines
  end

  def reliability(rows, predictions)
    bins = Array.new(@settings[:bins].length + 1) { { count: 0, correct: 0, share: 0.0 } }
    rows.each do |row|
      prediction = predictions.fetch(row.id)
      index = @settings[:bins].index { |boundary| prediction.share < boundary } || @settings[:bins].length
      bins[index][:count] += 1
      bins[index][:correct] += 1 if prediction.label == row.label
      bins[index][:share] += prediction.share
    end
    bounds = [0.0] + @settings[:bins]
    bins.each_with_index.map do |bin, index|
      line = "bin #{Report.real(bounds[index], 2)} rows #{bin[:count]}"
      unless bin[:count].zero?
        line += " correct #{Report.ratio(bin[:correct], bin[:count])} share #{Report.real(bin[:share] / bin[:count].to_f)}"
      end
      line
    end
  end

  def grid_parts
    parts = [["data train #{@training.length} test #{@testing.length} labelled #{@labelled.length} targets #{@targets.length} features #{@features.length} classes #{@labels.length}",
              'classes ' + label_counts(@training)]]
    @settings[:scalings].each do |name|
      scaling = Scaling.new(@training, name)
      lines = ["scaling #{name}"]
      @features.each_with_index do |feature, index|
        lines << "#{feature} center #{Report.real(scaling.centers[index], 6)} scale #{Report.real(scaling.scales[index], 6)}"
      end
      parts << lines
    end
    fold_lines = @folds.each_with_index.map do |rows, index|
      "fold #{index + 1} size #{rows.length} #{label_counts(rows)}"
    end
    parts << ["folds #{@settings[:folds]}"] + fold_lines
    parts << ["grid #{@grid.length}", 'best_classifier ' + selection_text(@classifier_result, :classifier),
              'best_regressor ' + selection_text(@regressor_result, :regressor)]
    [[:classifier, 'accuracy', accuracy_rank(@results)], [:regressor, 'rmse', rmse_rank(@results)]].each do |kind, label, ranking|
      lines = ranking.first(@settings[:top]).each_with_index.map do |result, index|
        "#{index + 1} #{selection_text(result, kind)}"
      end
      parts << ["top #{@settings[:top]} by #{label}"] + lines
    end
    { k: :k_values, metric: :metrics, weighting: :weightings, scaling: :scalings }.each do |item, setting|
      lines = ["best per #{item}"]
      @settings[setting].each do |value|
        subset = @results.select { |result| result[:model][item] == value }
        classifier = accuracy_rank(subset).first
        regressor = rmse_rank(subset).first
        lines << "#{item}=#{value} classifier #{model_text(classifier[:model])} accuracy #{Report.real(classifier[:correct].to_f / @training.length.to_f)} " \
                 "regressor #{model_text(regressor[:model])} rmse #{Report.real(regressor[:rmse])}"
      end
      parts << lines
    end
    classifier_folds = @folds.each_with_index.map do |rows, index|
      "fold #{index + 1} correct #{Report.ratio(correct(rows, @classifier_result[:predictions]), rows.length)}"
    end
    regressor_folds = @folds.each_with_index.map do |rows, index|
      "fold #{index + 1} size #{rows.length} rmse #{Report.real(Validation.errors(rows, @regressor_result[:predictions])[:rmse])}"
    end
    parts << ['classifier folds'] + classifier_folds
    parts << ['regressor folds'] + regressor_folds
    parts << ['cross_validation classes'] + evaluation(@training, @classifier_result[:predictions])
    parts << ['cross_validation reliability'] + reliability(@training, @classifier_result[:predictions])
    parts << mcnemar_lines
    parts
  end

  def mcnemar_lines
    lines = ['mcnemar']
    @settings[:metrics].each do |metric|
      comparison = accuracy_rank(@results.select { |result| result[:model][:metric] == metric }).first
      b = c = 0
      @training.each do |row|
        selected_correct = @classifier_result[:predictions][row.id].label == row.label
        comparison_correct = comparison[:predictions][row.id].label == row.label
        b += 1 if selected_correct && !comparison_correct
        c += 1 if comparison_correct && !selected_correct
      end
      difference = [(b - c).abs - 1, 0].max
      numerator = difference * difference
      statistic = (b + c).zero? ? '0/1 0.0000' : Report.reduced(numerator, b + c)
      significant = 1000 * numerator > 3841 * (b + c) ? 'yes' : 'no'
      lines << "#{model_text(comparison[:model])} b #{b} c #{c} statistic #{statistic} significant #{significant}"
    end
    lines
  end

  def leave_one_out_parts
    by_k = @settings[:k_values].to_h { |k| [k, {}] }
    regressor_predictions = {}
    @training.each do |row|
      reference = @training.reject { |other| other.id == row.id }
      predictor = Validation::Predictor.new(reference, @used_features)
      by_k.each { |k, predictions| predictions[row.id] = predictor.predict(row, @classifier.merge(k: k)) }
      regressor_predictions[row.id] = predictor.predict(row, @regressor)
    end
    classifier_predictions = by_k[@classifier[:k]]
    errors = @training.reject { |row| classifier_predictions[row.id].label == row.label }
    classifier_lines = ["leave_one_out classifier #{model_text(@classifier)}", "errors #{Report.ratio(errors.length, @training.length)}",
                        'class_errors ' + label_counts(errors)]
    errors.sort_by(&:id).each do |row|
      prediction = classifier_predictions[row.id]
      classifier_lines << "#{row.id} true #{row.label} predicted #{prediction.label} share #{Report.real(prediction.share)}"
    end
    metrics = Validation.errors(@training, regressor_predictions)
    regressor_lines = ["leave_one_out regressor #{model_text(@regressor)}", "rmse #{Report.real(metrics[:rmse])} mae #{Report.real(metrics[:mae])}",
                       "largest #{@settings[:top]} residuals"]
    ranking = @training.sort_by { |row| [-Report.rounded((regressor_predictions[row.id].estimate - row.target).abs), row.id] }
    ranking.first(@settings[:top]).each do |row|
      estimate = regressor_predictions[row.id].estimate
      regressor_lines << "#{row.id} target #{Report.real(row.target)} estimate #{Report.real(estimate)} residual #{Report.real(estimate - row.target)}"
    end
    k_lines = ["leave_one_out by k metric=#{@classifier[:metric]} weighting=#{@classifier[:weighting]} scaling=#{@classifier[:scaling]}"]
    by_k.each do |k, predictions|
      k_lines << "k=#{k} correct #{Report.ratio(correct(@training, predictions), @training.length)} rmse #{Report.real(Validation.errors(@training, predictions)[:rmse])}"
    end
    [classifier_lines, regressor_lines, k_lines]
  end

  def nested_lines
    lines = ["nested_cross_validation folds #{@settings[:folds]}"]
    correct_total = 0
    nested_predictions = {}
    @folds.each_with_index do |validation, index|
      ids = validation.map(&:id).to_set
      reference = @training.reject { |row| ids.include?(row.id) }
      results = cross_validate(reference)
      classifier = accuracy_rank(results).first
      regressor = rmse_rank(results).first
      predictor = Validation::Predictor.new(reference, @used_features)
      predictions = predict_rows(validation, predictor, classifier[:model])
      count = correct(validation, predictions)
      correct_total += count
      nested_predictions.merge!(predict_rows(validation, predictor, regressor[:model]))
      rmse = Validation.errors(validation, nested_predictions)[:rmse]
      lines << "fold #{index + 1} classifier #{model_text(classifier[:model])} inner #{Report.real(classifier[:correct].to_f / reference.length.to_f)} outer #{Report.ratio(count, validation.length)}"
      lines << "fold #{index + 1} regressor #{model_text(regressor[:model])} inner #{Report.real(regressor[:rmse])} outer #{Report.real(rmse)}"
    end
    lines << "nested accuracy #{Report.ratio(correct_total, @training.length)} rmse #{Report.real(Validation.errors(@training, nested_predictions)[:rmse])}"
    lines
  end

  def feature_selection_lines
    current = @used_features.dup
    selected = current
    best_count = @classifier_result[:correct]
    names = current.map { |index| @features[index] }.join(' ')
    lines = ["feature_selection #{model_text(@classifier)}", "start features #{names} correct #{Report.ratio(best_count, @training.length)}"]
    step = 0
    while current.length >= 3
      candidates = current.map do |feature|
        remaining = current.reject { |index| index == feature }
        [feature, cross_validate(@training, [@classifier], remaining).first[:correct]]
      end
      removed, count = candidates.min_by { |feature, score| [-score, feature] }
      current = current.reject { |feature| feature == removed }
      step += 1
      candidate_text = candidates.map { |feature, score| "#{@features[feature]} #{score}" }.join(' ')
      lines << "step #{step} remove #{@features[removed]} correct #{Report.ratio(count, @training.length)} candidates #{candidate_text}"
      if count >= best_count
        selected = current
        best_count = count
      end
    end
    names = selected.map { |index| @features[index] }.join(' ')
    predictions = predict_rows(@labelled, Validation::Predictor.new(@training, selected), @classifier)
    lines << "selected features #{names} correct #{Report.ratio(best_count, @training.length)}"
    lines << "selected test #{Report.ratio(correct(@labelled, predictions), @labelled.length)}"
    lines
  end

  def test_parts
    parts = [["test classification #{model_text(@classifier)}",
              "labelled #{@labelled.length} correct #{Report.ratio(correct(@labelled, @test_classifier), @labelled.length)}"] + evaluation(@labelled, @test_classifier)]
    parts << ['test reliability'] + reliability(@labelled, @test_classifier)
    uncertain = ["uncertain #{@settings[:top]} test rows"]
    ranking = @testing.each_with_index.sort_by do |row, index|
      prediction = @test_classifier[row.id]
      [Report.rounded(prediction.share - prediction.runner_share), index]
    end
    ranking.first(@settings[:top]).each do |row, _|
      prediction = @test_classifier[row.id]
      uncertain << "#{row.id} predicted #{prediction.label} share #{Report.real(prediction.share)} runner_up #{prediction.runner || '-'} " \
                   "share #{Report.real(prediction.runner_share)} margin #{Report.real(prediction.share - prediction.runner_share)} true #{row.label || '-'}"
    end
    parts << uncertain
    metrics = Validation.errors(@targets, @test_regressor)
    regression = ["test regression #{model_text(@regressor)}",
                  "targets #{@targets.length} rmse #{Report.real(metrics[:rmse])} mae #{Report.real(metrics[:mae])} r2 #{Report.real(metrics[:r2])}"]
    @labels.each do |label|
      rows = @targets.select { |row| row.label == label }
      regression << "class #{label} targets #{rows.length} rmse #{Report.real(Validation.errors(rows, @test_regressor)[:rmse])}"
    end
    parts << regression
    misclassified = ['misclassified test rows']
    count = 0
    @labelled.each do |row|
      prediction = @test_classifier[row.id]
      next if prediction.label == row.label

      count += 1
      misclassified << "#{row.id} true #{row.label} predicted #{prediction.label} share #{Report.real(prediction.share)}"
      prediction.neighbors.each { |neighbor, distance| misclassified << "  #{neighbor.id} #{neighbor.label} #{Report.real(distance)}" }
    end
    misclassified << "count #{count}"
    parts << misclassified
    parts
  end

  def learning_curve_lines
    lines = ['n,train_size,correct,accuracy,rmse']
    @settings[:curve].each do |size|
      counts = Hash.new(0)
      reference = @training.select do |row|
        counts[row.label] += 1
        counts[row.label] <= size
      end
      predictor = Validation::Predictor.new(reference, @used_features)
      predictions = predict_rows(@labelled, predictor, @classifier)
      estimates = predict_rows(@targets, predictor, @regressor)
      count = correct(@labelled, predictions)
      lines << [size, reference.length, count, Report.real(count.to_f / @labelled.length.to_f),
                Report.real(Validation.errors(@targets, estimates)[:rmse])].join(',')
    end
    lines
  end

  def space_order(row, ids)
    @full_predictor.order(row, @classifier).select { |neighbor, _| neighbor.id != row.id && ids.include?(neighbor.id) }
  end

  def edit_prototypes(original)
    edited = original
    lines = ["editing k=#{@settings[:edit_k]}"]
    pass = 0
    loop do
      pass += 1
      ids = edited.map(&:id).to_set
      removed = edited.filter_map do |row|
        prediction = Neighbors.vote(space_order(row, ids), @settings[:edit_k], @classifier[:weighting])
        [row, prediction] if prediction.label != row.label
      end
      lines << "pass #{pass} removed #{removed.length}"
      removed.each { |row, prediction| lines << "  #{row.id} true #{row.label} predicted #{prediction.label} share #{Report.real(prediction.share)}" }
      break if removed.empty?

      removed_ids = removed.map { |row, _| row.id }.to_set
      edited = edited.reject { |row| removed_ids.include?(row.id) }
    end
    lines << "edited size #{edited.length} removed #{@training.length - edited.length}"
    [edited, lines]
  end

  def condense(rows)
    store = Set.new([rows.first.id])
    scans = 0
    loop do
      scans += 1
      added = 0
      rows.each do |row|
        next if store.include?(row.id)

        nearest = @full_predictor.order(row, @classifier).find { |neighbor, _| store.include?(neighbor.id) }.first
        next if nearest.label == row.label

        store.add(row.id)
        added += 1
      end
      break if added.zero?
    end
    [rows.select { |row| store.include?(row.id) }, scans]
  end

  def prototype_set_line(name, rows)
    ids = rows.map(&:id).to_set
    knn = nearest = 0
    @labelled.each do |row|
      order = space_order(row, ids)
      prediction = Neighbors.vote(order, @classifier[:k], @classifier[:weighting])
      knn += 1 if prediction.label == row.label
      nearest += 1 if order.first.first.label == row.label
    end
    "set #{name} size #{rows.length} #{label_counts(rows)} knn #{Report.ratio(knn, @labelled.length)} 1nn #{Report.ratio(nearest, @labelled.length)}"
  end

  def border_lines(original)
    ids = original.map(&:id).to_set
    lines = ['borders']
    total = 0
    @labels.each do |label|
      rows = original.select { |row| row.label == label }
      count = 0
      same = other = 0.0
      rows.each do |row|
        order = space_order(row, ids)
        count += 1 if order.first.first.label != label
        same += order.find { |neighbor, _| neighbor.label == label }[1]
        other += order.find { |neighbor, _| neighbor.label != label }[1]
      end
      total += count
      lines << "class #{label} size #{rows.length} border #{count} same #{Report.real(same / rows.length.to_f)} other #{Report.real(other / rows.length.to_f)}"
    end
    lines << "border total #{Report.ratio(total, @training.length)}"
    lines
  end

  def hub_lines
    counts = @training.to_h { |row| [row.id, 0] }
    @testing.each { |row| @test_classifier[row.id].neighbors.each { |neighbor, _| counts[neighbor.id] += 1 } }
    lines = ["hubs k=#{@classifier[:k]} queries #{@testing.length}"]
    @training.sort_by { |row| [-counts[row.id], row.id] }.first(@settings[:top]).each do |row|
      lines << "#{row.id} #{row.label} #{counts[row.id]}"
    end
    lines << "anti_hubs #{counts.values.count(&:zero?)}"
    lines
  end

  def prototype_parts
    original = @training.sort_by(&:id)
    edited, editing_lines = edit_prototypes(original)
    condensed, original_scans = condense(original)
    edited_condensed, edited_scans = condense(edited)
    sets = { 'original' => original, 'edited' => edited, 'condensed' => condensed, 'edited_condensed' => edited_condensed }
    parts = [["space #{model_text(@classifier)}"], editing_lines,
             ["condensing original scans #{original_scans} size #{condensed.length}",
              "condensing edited scans #{edited_scans} size #{edited_condensed.length}"],
             sets.map { |name, rows| prototype_set_line(name, rows) }]
    %w[condensed edited_condensed].each do |name|
      parts << ["prototypes #{name}"] + sets[name].map(&:id).each_slice(10).map { |ids| ids.join(' ') }
    end
    parts << border_lines(original)
    parts << hub_lines
    parts
  end

  def grid_lines
    lines = @results.map do |result|
      model = result[:model]
      [model[:k], model[:metric], model[:weighting], model[:scaling], result[:correct],
       Report.real(result[:correct].to_f / @training.length.to_f), Report.real(result[:rmse])].join(',')
    end
    ['k,metric,weighting,scaling,correct,accuracy,rmse'] + lines
  end

  def prediction_lines
    lines = @testing.map do |row|
      prediction = @test_classifier[row.id]
      [row.id, prediction.label, Report.real(prediction.share), Report.real(@test_regressor[row.id].estimate)].join(',')
    end
    ['id,label,vote_share,estimate'] + lines
  end

  def joined_parts(parts)
    parts.each_with_index.flat_map { |part, index| index.zero? ? part : [''] + part }
  end

  def run
    @results = cross_validate(@training)
    @classifier_result = accuracy_rank(@results).first
    @regressor_result = rmse_rank(@results).first
    @classifier = @classifier_result[:model]
    @regressor = @regressor_result[:model]
    @full_predictor = Validation::Predictor.new(@training, @used_features)
    @test_classifier = predict_rows(@testing, @full_predictor, @classifier)
    @test_regressor = predict_rows(@testing, @full_predictor, @regressor)
    metrics = grid_parts + leave_one_out_parts + [nested_lines, feature_selection_lines] + test_parts
    Report.write('cv_grid.csv' => grid_lines, 'predictions.csv' => prediction_lines, 'metrics.txt' => joined_parts(metrics),
                 'learning_curve.csv' => learning_curve_lines, 'prototypes.txt' => joined_parts(prototype_parts))
  end
end

KNNStudy.new.run
