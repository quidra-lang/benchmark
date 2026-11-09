require 'set'
require_relative 'tokenizer'
require_relative 'vocabulary'
require_relative 'naive_bayes'
require_relative 'rocchio'
require_relative 'evaluation'

class NewsClassifier
  MODELS = %w[multinomial bernoulli complement rocchio vote].freeze
  NB_MODELS = MODELS.first(3).freeze
  BASE_MODELS = MODELS.first(4).freeze
  PAIRS = BASE_MODELS.combination(2).to_a.freeze
  Vote = Struct.new(:label, :score)

  def run
    read_input
    cross_validate
    final_predictions
    @learning = learning_curve
    @feature_study = feature_study
    write_outputs
  end

  private

  def hundredfold(text)
    whole, fraction = text.split('.')
    100 * whole.to_i + fraction.to_i
  end

  def read_input
    stopwords = File.readlines('input/stopwords.txt', chomp: true).to_set
    @params = File.readlines('input/params.txt', chomp: true).to_h do |line|
      key, *values = line.split(' ')
      parsed = if %w[ALPHAS THRESHOLDS EM_WEIGHT].include?(key)
                 values.map { |value| hundredfold(value) }
               elsif key == 'BIGRAMS'
                 values
               else
                 values.map(&:to_i)
               end
      [key, parsed]
    end
    @use_bigrams = @params.fetch('BIGRAMS').first == 'yes'
    @train = File.readlines('input/train.txt', chomp: true).each_with_index.map do |line, index|
      label, text = line.split("\t", 2)
      Tokenizer.document(text, stopwords, label: label, number: index + 1)
    end
    @test = File.readlines('input/test.txt', chomp: true).each_with_index.map do |line, index|
      id, label, text = line.split("\t", 3)
      Tokenizer.document(text, stopwords, id: id, label: label, number: index + 1)
    end
    @unlabelled = File.readlines('input/unlabelled.txt', chomp: true).map do |text|
      Tokenizer.document(text, stopwords)
    end
    @classes = @train.map(&:label).uniq.sort
    class_ids = @classes.each_with_index.to_h
    (@train + @test).each { |document| document.class_id = class_ids[document.label] }
    @labelled = @test.each_index.reject { |index| @test[index].class_id.nil? }
    @truth = @labelled.map { |index| @test[index].class_id }
    @training_truth = @train.map(&:class_id)
  end

  def setting(key)
    @params.fetch(key).first
  end

  def context(documents, use_bigrams = @use_bigrams, features = setting('FEATURES'))
    vocabulary = Vocabulary.new(documents, @classes.length, setting('MIN_DF'), features, use_bigrams)
    encoded = documents.map { |document| vocabulary.encode(document) }
    counts = NaiveBayes.count(documents, encoded, @classes.length, vocabulary.size)
    rocchio = Rocchio.new(documents, encoded, vocabulary, @classes.length)
    [vocabulary, counts, rocchio]
  end

  def cv_record
    { labels: Array.new(@train.length), folds: Array.new(5, 0) }
  end

  def record_validation(record, model, documents, encoded, fold)
    documents.each_with_index do |document, index|
      prediction = model.predict(encoded[index]).label
      record[:labels][document.number - 1] = prediction
      record[:folds][fold] += 1 if prediction == document.class_id
    end
  end

  def cross_validate
    @cv = NB_MODELS.to_h { |model| [model, @params.fetch('ALPHAS').to_h { |alpha| [alpha, cv_record] }] }
    @cv['rocchio'] = { nil => cv_record }
    @folds = []
    5.times do |fold|
      training, validation = @train.partition { |document| (document.number - 1) % 5 != fold }
      vocabulary, counts, rocchio = context(training)
      @folds << [training.length, validation.length, vocabulary.candidate_count, vocabulary.size]
      encoded = validation.map { |document| vocabulary.encode(document) }
      NB_MODELS.each do |model|
        @params.fetch('ALPHAS').each do |alpha|
          trained = NaiveBayes.train(model, counts, alpha)
          record_validation(@cv[model][alpha], trained, validation, encoded, fold)
        end
      end
      record_validation(@cv['rocchio'][nil], rocchio, validation, encoded, fold)
    end
    @cv.each_value do |variants|
      variants.each_value do |record|
        record[:evaluation] = Evaluation.new(@training_truth, record[:labels], @classes.length)
      end
    end
    @selected = NB_MODELS.to_h do |model|
      alpha = @params.fetch('ALPHAS').min_by do |candidate|
        [-Evaluation.rounded_key(@cv[model][candidate][:evaluation].macro), candidate]
      end
      [model, alpha]
    end
    @selected['rocchio'] = nil
  end

  def train_selected(counts, rocchio)
    models = NB_MODELS.to_h { |model| [model, NaiveBayes.train(model, counts, @selected.fetch(model))] }
    models['rocchio'] = rocchio
    models
  end

  def final_predictions
    @vocabulary, @counts, rocchio = context(@train)
    @models = train_selected(@counts, rocchio)
    @encoded_test = @test.map { |document| @vocabulary.encode(document) }
    @encoded_unlabelled = @unlabelled.map { |document| @vocabulary.encode(document) }
    @predictions = BASE_MODELS.to_h do |model|
      [model, @encoded_test.map { |document| @models.fetch(model).predict(document) }]
    end
    @predictions['vote'] = @test.each_index.map do |index|
      labels = BASE_MODELS.map { |model| @predictions[model][index].label }
      counts = labels.tally
      maximum = counts.values.max
      label = labels.find { |candidate| counts.fetch(candidate) == maximum }
      Vote.new(label, maximum.fdiv(4))
    end
    @test_evaluations = MODELS.to_h do |model|
      predicted = @labelled.map { |index| @predictions[model][index].label }
      [model, Evaluation.new(@truth, predicted, @classes.length)]
    end
  end

  def evaluate_study(documents, use_bigrams, features)
    vocabulary, counts, rocchio = context(documents, use_bigrams, features)
    models = train_selected(counts, rocchio)
    encoded = @labelled.map { |index| vocabulary.encode(@test[index]) }
    evaluations = BASE_MODELS.to_h do |model|
      predicted = encoded.map { |document| models.fetch(model).predict(document).label }
      [model, Evaluation.new(@truth, predicted, @classes.length)]
    end
    [vocabulary.size, evaluations]
  end

  def evaluation_columns(evaluation)
    [evaluation.correct, Evaluation.real(evaluation.micro), Evaluation.real(evaluation.macro)]
  end

  def learning_curve
    lines = ['size,vocabulary,model,correct,accuracy,macro_f1']
    @params.fetch('CURVE').each do |size|
      vocabulary_size, evaluations = evaluate_study(@train.first(size), @use_bigrams, setting('FEATURES'))
      BASE_MODELS.each do |model|
        lines << [size, vocabulary_size, model, *evaluation_columns(evaluations.fetch(model))].join(',')
      end
    end
    lines
  end

  def feature_study
    lines = ['terms,features,vocabulary,model,correct,accuracy,macro_f1']
    [['unigrams', false], ['bigrams', true]].each do |kind, use_bigrams|
      @params.fetch('SIZES').each do |features|
        vocabulary_size, evaluations = evaluate_study(@train, use_bigrams, features)
        BASE_MODELS.each do |model|
          lines << [kind, features, vocabulary_size, model, *evaluation_columns(evaluations.fetch(model))].join(',')
        end
      end
    end
    lines
  end

  def alpha_text(model)
    alpha = @selected[model]
    alpha.nil? ? '-' : Evaluation.two(alpha)
  end

  def vocabulary_lines
    lines = ["documents #{@train.length} terms #{@vocabulary.all_term_count} " \
             "candidates #{@vocabulary.candidate_count} vocabulary #{@vocabulary.size}"]
    @vocabulary.ranking.each_with_index do |entry, index|
      lines << "#{index + 1} #{entry.term} #{entry.df} #{Evaluation.real(entry.chi_square)} #{@classes[entry.best_class]}"
    end
    lines
  end

  def cv_lines
    lines = ['model,alpha,correct,accuracy,macro_f1,selected']
    BASE_MODELS.each do |model|
      @cv.fetch(model).each do |alpha, record|
        selected = alpha == @selected[model] ? 'yes' : 'no'
        text = alpha.nil? ? '-' : Evaluation.two(alpha)
        lines << [model, text, *evaluation_columns(record[:evaluation]), selected].join(',')
      end
    end
    lines
  end

  def prediction_lines
    lines = ['id,model,label,score']
    @test.each_with_index do |document, index|
      MODELS.each do |model|
        prediction = @predictions[model][index]
        lines << [document.id, model, @classes[prediction.label], Evaluation.real(prediction.score)].join(',')
      end
    end
    lines
  end

  def class_counts_text(counts)
    @classes.each_with_index.flat_map { |name, class_id| [name, counts[class_id] || 0] }.join(' ')
  end

  def data_part
    lines = ["documents train #{@train.length} test #{@test.length} labelled #{@labelled.length} " \
             "unlabelled #{@unlabelled.length} classes #{@classes.length}"]
    test_counts = @truth.tally
    @classes.each_with_index do |name, class_id|
      lines << "class #{name} train #{@counts.class_counts[class_id]} test #{test_counts.fetch(class_id, 0)}"
    end
    raw = @train.sum(&:raw_count)
    stops = @train.sum(&:stop_count)
    shorts = @train.sum(&:short_count)
    words = @train.flat_map(&:words)
    bigrams = @use_bigrams ? @train.flat_map(&:bigrams) : []
    lines << "train_tokens raw #{raw} stopwords #{stops} short #{shorts} unigrams #{words.length} bigrams #{bigrams.length}"
    lines << "train_terms unigrams #{words.uniq.length} bigrams #{bigrams.uniq.length} " \
             "candidates #{@vocabulary.candidate_count} vocabulary #{@vocabulary.size}"
    total = @test.sum { |document| document.terms(@use_bigrams).length }
    in_vocabulary = @encoded_test.sum { |document| document.sequence.length }
    lines << "test_terms total #{total} in_vocabulary #{in_vocabulary}"
    oov = Hash.new(0)
    @test.each do |document|
      document.words.each { |word| oov[word] += 1 unless @vocabulary.positions.key?(word) }
    end
    ranked = oov.sort_by { |word, count| [-count, word] }.first(setting('TOP'))
    lines << ['test_oov', *ranked.flatten].join(' ')
    lines
  end

  def folds_part
    lines = ['folds 5']
    @folds.each_with_index do |values, index|
      train, validate, candidates, vocabulary = values
      lines << "fold #{index + 1} train #{train} validate #{validate} candidates #{candidates} vocabulary #{vocabulary}"
    end
    lines
  end

  def selection_part
    lines = ['selection']
    BASE_MODELS.each do |model|
      record = @cv[model][@selected[model]]
      evaluation = record[:evaluation]
      lines << "#{model} alpha #{alpha_text(model)} correct #{Evaluation.proportion(evaluation.correct, @train.length)} " \
               "macro_f1 #{Evaluation.real(evaluation.macro)} folds #{record[:folds].join(' ')}"
    end
    lines
  end

  def cross_validation_parts
    BASE_MODELS.map do |model|
      evaluation = @cv[model][@selected[model]][:evaluation]
      ["cross_validation #{model} alpha #{alpha_text(model)}", *evaluation.lines(@classes)]
    end
  end

  def test_parts
    MODELS.map do |model|
      evaluation = @test_evaluations.fetch(model)
      lines = ["test #{model} alpha #{alpha_text(model)}",
               "labelled #{@labelled.length} correct #{Evaluation.proportion(evaluation.correct, @labelled.length)}"]
      if model != 'vote'
        top_two = @labelled.count do |index|
          @predictions[model][index].ranking.first(2).include?(@test[index].class_id)
        end
        lines << "top2 #{Evaluation.proportion(top_two, @labelled.length)}"
      end
      lines.concat(evaluation.lines(@classes))
    end
  end

  def correct_count(model, rows)
    rows.count { |index| @predictions[model][index].label == @test[index].class_id }
  end

  def probability_part(model)
    thresholds = @params.fetch('THRESHOLDS')
    bounds = [0, *thresholds]
    real_thresholds = thresholds.map { |value| value.fdiv(100) }
    bins = Array.new(bounds.length) { [] }
    loss_total = 0.0
    brier_total = 0.0
    @labelled.each do |index|
      prediction = @predictions[model][index]
      truth = @test[index].class_id
      loss_total += Math.log(prediction.normalizer) - (prediction.scores[truth] - prediction.scores[prediction.label])
      brier = 0.0
      @classes.each_index do |class_id|
        difference = prediction.posterior[class_id] - (class_id == truth ? 1 : 0)
        brier += difference * difference
      end
      brier_total += brier
      bucket = real_thresholds.count { |threshold| prediction.score >= threshold }
      bins[bucket] << index
    end
    lines = ["probability #{model} alpha #{alpha_text(model)}",
             "log_loss #{Evaluation.real(loss_total / @labelled.length)} brier #{Evaluation.real(brier_total / @labelled.length)}"]
    bins.each_with_index do |rows, index|
      prefix = "bin #{Evaluation.two(bounds[index])} rows #{rows.length}"
      if rows.empty?
        lines << prefix
      else
        sum = 0.0
        rows.each { |row| sum += @predictions[model][row].score }
        lines << "#{prefix} correct #{Evaluation.proportion(correct_count(model, rows), rows.length)} " \
                 "mean #{Evaluation.real(sum / rows.length)}"
      end
    end
    thresholds.each_with_index do |threshold, index|
      rows = @labelled.select { |row| @predictions[model][row].score >= real_thresholds[index] }
      correct = rows.empty? ? '-' : Evaluation.proportion(correct_count(model, rows), rows.length)
      lines << "threshold #{Evaluation.two(threshold)} covered #{Evaluation.proportion(rows.length, @labelled.length)} correct #{correct}"
    end
    lines
  end

  def lengths_part
    boundaries = @params.fetch('LENGTHS')
    bounds = [0, *boundaries]
    buckets = Array.new(bounds.length) { [] }
    @labelled.each do |index|
      length = @encoded_test[index].sequence.length
      buckets[boundaries.count { |boundary| length >= boundary }] << index
    end
    lines = ['lengths']
    buckets.each_with_index do |rows, index|
      line = "length #{bounds[index]} rows #{rows.length}"
      unless rows.empty?
        MODELS.each { |model| line += " #{model} #{Evaluation.proportion(correct_count(model, rows), rows.length)}" }
      end
      lines << line
    end
    lines
  end

  def comparison_part
    lines = ['comparison']
    PAIRS.each do |left, right|
      agreement = @test.each_index.count { |index| @predictions[left][index].label == @predictions[right][index].label }
      b = c = 0
      @labelled.each do |index|
        x = @predictions[left][index].label == @test[index].class_id
        y = @predictions[right][index].label == @test[index].class_id
        b += 1 if x && !y
        c += 1 if y && !x
      end
      numerator = [(b - c).abs - 1, 0].max**2
      statistic = b + c == 0 ? Evaluation.fraction(0, 1) : Evaluation.fraction(numerator, b + c)
      lines << "#{left} #{right} agree #{Evaluation.proportion(agreement, @test.length)} b #{b} c #{c} statistic #{statistic}"
    end
    errors = Array.new(5, 0)
    @labelled.each do |index|
      count = BASE_MODELS.count { |model| @predictions[model][index].label != @test[index].class_id }
      errors[count] += 1
    end
    lines << ['errors', *errors.each_with_index.flat_map { |count, index| [index, count] }].join(' ')
    lines
  end

  def bootstrap_part
    repetitions, seed = @params.fetch('BOOTSTRAP')
    state = seed
    samples = Array.new(MODELS.length) { [] }
    repetitions.times do
      counts = Array.new(MODELS.length, 0)
      @labelled.length.times do
        state = (48_271 * state) % 2_147_483_647
        index = @labelled[state % @labelled.length]
        MODELS.each_with_index do |model, model_id|
          counts[model_id] += 1 if @predictions[model][index].label == @test[index].class_id
        end
      end
      counts.each_with_index { |count, model_id| samples[model_id] << count }
    end
    lines = ["bootstrap resamples #{repetitions} seed #{seed}"]
    MODELS.each_with_index do |model, model_id|
      sorted = samples[model_id].sort
      low = sorted[repetitions / 40]
      high = sorted[repetitions - 1 - repetitions / 40]
      mean = samples[model_id].sum.fdiv(repetitions * @labelled.length)
      lines << "#{model} mean #{Evaluation.real(mean)} low #{Evaluation.proportion(low, @labelled.length)} " \
               "high #{Evaluation.proportion(high, @labelled.length)}"
    end
    PAIRS.each do |left, right|
      left_values = samples[MODELS.index(left)]
      right_values = samples[MODELS.index(right)]
      wins = ties = losses = 0
      repetitions.times do |index|
        if left_values[index] > right_values[index]
          wins += 1
        elsif left_values[index] == right_values[index]
          ties += 1
        else
          losses += 1
        end
      end
      lines << "pair #{left} #{right} wins #{wins} ties #{ties} losses #{losses}"
    end
    lines
  end

  def hard_part
    hard = @train.each_index.select do |index|
      BASE_MODELS.all? { |model| @cv[model][@selected[model]][:labels][index] != @train[index].class_id }
    end
    counts = Array.new(@classes.length, 0)
    hard.each { |index| counts[@train[index].class_id] += 1 }
    lines = ["hard_documents #{hard.length} #{class_counts_text(counts)}"]
    hard.first(setting('TOP')).each do |index|
      predicted = BASE_MODELS.map { |model| @classes[@cv[model][@selected[model]][:labels][index]] }
      lines << "#{index + 1} true #{@train[index].label} predicted #{predicted.join(' ')}"
    end
    lines
  end

  def uncertain_part
    predictions = @predictions.fetch('multinomial')
    rows = @test.each_index.sort_by { |index| [Evaluation.rounded_key(predictions[index].margin), index] }.first(setting('TOP'))
    lines = ["uncertain multinomial #{rows.length}"]
    rows.each do |index|
      prediction = predictions[index]
      lines << "#{@test[index].id} predicted #{@classes[prediction.label]} runner_up #{@classes[prediction.ranking[1]]} " \
               "margin #{Evaluation.real(prediction.margin)} posterior #{Evaluation.real(prediction.score)} true #{@test[index].label}"
    end
    lines
  end

  def ratio_order(terms, numerators, denominators)
    terms.sort do |left, right|
      comparison = (numerators[right] * denominators[left]) <=> (numerators[left] * denominators[right])
      comparison.zero? ? @vocabulary.terms[left] <=> @vocabulary.terms[right] : comparison
    end
  end

  def evidence_part
    model = @models.fetch('multinomial')
    alpha = @selected.fetch('multinomial')
    rows = @labelled.select { |index| @predictions['multinomial'][index].label != @test[index].class_id }
    lines = ["misclassified multinomial #{rows.length}"]
    rows.each do |index|
      prediction = @predictions['multinomial'][index]
      truth = @test[index].class_id
      lines << "#{@test[index].id} true #{@test[index].label} predicted #{@classes[prediction.label]} posterior #{Evaluation.real(prediction.score)}"
      numerator = @counts.n[prediction.label].map { |count| 100 * count + alpha }
      denominator = @counts.n[truth].map { |count| 100 * count + alpha }
      encoded = @encoded_test[index]
      ratio_order(encoded.unique, numerator, denominator).first(3).each do |term|
        evidence = model.weights[prediction.label][term] - model.weights[truth][term]
        lines << "  #{@vocabulary.terms[term]} count #{encoded.counts.fetch(term)} evidence #{Evaluation.real(evidence)}"
      end
    end
    lines
  end

  def top_feature_parts
    parts = []
    %w[multinomial bernoulli].each do |model|
      alpha = @selected.fetch(model)
      parts << ["model #{model} alpha #{Evaluation.two(alpha)} vocabulary #{@vocabulary.size} top #{setting('TOP')}"]
      @classes.each_with_index do |name, class_id|
        if model == 'multinomial'
          counts = @counts.n[class_id]
          others = @counts.term_totals.each_with_index.map { |total, term| total - counts[term] }
          total = @counts.totals[class_id]
          other_total = @counts.total - total
          smoothing = alpha * @vocabulary.size
        else
          counts = @counts.d[class_id]
          others = @counts.df.each_with_index.map { |total, term| total - counts[term] }
          total = @counts.class_counts[class_id]
          other_total = @counts.documents - total
          smoothing = 2 * alpha
        end
        numerator = counts.map { |count| 100 * count + alpha }
        denominator = others.map { |count| 100 * count + alpha }
        lines = ["class #{name} total #{total} other #{other_total}"]
        terms = ratio_order(@vocabulary.terms.each_index.to_a, numerator, denominator).first(setting('TOP'))
        terms.each_with_index do |term, rank|
          odds = Math.log(numerator[term].fdiv(100 * total + smoothing)) -
                 Math.log(denominator[term].fdiv(100 * other_total + smoothing))
          lines << "#{rank + 1} #{@vocabulary.terms[term]} #{counts[term]} #{others[term]} #{Evaluation.real(odds)}"
        end
        parts << lines
      end
    end
    parts
  end

  def em_part
    alpha = @selected.fetch('multinomial')
    weight_hundredfold = setting('EM_WEIGHT')
    weight = weight_hundredfold.fdiv(100)
    denominator = @train.length + (weight_hundredfold * @unlabelled.length).fdiv(100)
    model = @models.fetch('multinomial')
    previous = nil
    lines = ["semi_supervised multinomial alpha #{Evaluation.two(alpha)} weight #{Evaluation.two(weight_hundredfold)} " \
             "unlabelled #{@unlabelled.length}"]
    0.upto(setting('EM_ITERATIONS')) do |iteration|
      predictions = @encoded_unlabelled.map { |document| model.predict(document) }
      assignments = predictions.map(&:label)
      predicted_test = @labelled.map { |index| model.predict(@encoded_test[index]).label }
      evaluation = Evaluation.new(@truth, predicted_test, @classes.length)
      changed = previous.nil? ? '-' : assignments.each_index.count { |index| assignments[index] != previous[index] }
      assigned_counts = Array.new(@classes.length, 0)
      assignments.each { |class_id| assigned_counts[class_id] += 1 }
      lines << "iteration #{iteration} correct #{Evaluation.proportion(evaluation.correct, @labelled.length)} " \
               "macro_f1 #{Evaluation.real(evaluation.macro)} changed #{changed} assigned #{class_counts_text(assigned_counts)}"
      break if iteration == setting('EM_ITERATIONS')

      previous = assignments
      occurrences = @counts.n.map { |row| row.map(&:to_f) }
      class_counts = @counts.class_counts.map(&:to_f)
      @encoded_unlabelled.each_with_index do |document, index|
        @classes.each_index do |class_id|
          posterior_weight = weight * predictions[index].posterior[class_id]
          document.unique.each do |term|
            occurrences[class_id][term] += posterior_weight * document.counts.fetch(term)
          end
          class_counts[class_id] += posterior_weight
        end
      end
      totals = occurrences.map do |row|
        sum = 0.0
        row.each { |value| sum += value }
        sum
      end
      weights = occurrences.each_with_index.map do |row, class_id|
        row.map { |value| Math.log((100 * value + alpha) / (100 * totals[class_id] + alpha * @vocabulary.size)) }
      end
      priors = class_counts.map { |value| Math.log(value / denominator) }
      model = NaiveBayes::Model.new('multinomial', weights, priors)
    end
    lines
  end

  def metrics_parts
    parts = [data_part, folds_part, selection_part]
    parts.concat(cross_validation_parts)
    parts.concat(test_parts)
    NB_MODELS.each { |model| parts << probability_part(model) }
    parts.concat([lengths_part, comparison_part, bootstrap_part, hard_part, uncertain_part, evidence_part, em_part])
    parts
  end

  def write_lines(path, lines)
    File.binwrite(path, lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def write_parts(path, parts)
    File.binwrite(path, parts.map { |lines| lines.join("\n") }.join("\n\n") + "\n")
  end

  def write_outputs
    Dir.mkdir('output') unless Dir.exist?('output')
    write_lines('output/vocabulary.txt', vocabulary_lines)
    write_lines('output/cv_results.csv', cv_lines)
    write_lines('output/predictions.csv', prediction_lines)
    write_lines('output/learning_curve.csv', @learning)
    write_lines('output/feature_study.csv', @feature_study)
    write_parts('output/metrics.txt', metrics_parts)
    write_parts('output/top_features.txt', top_feature_parts)
  end
end

NewsClassifier.new.run if $PROGRAM_NAME == __FILE__
