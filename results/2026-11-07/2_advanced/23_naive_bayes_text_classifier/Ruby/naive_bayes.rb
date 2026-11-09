module NaiveBayes
  Counts = Struct.new(:documents, :class_counts, :n, :d, :totals, :term_totals, :df, :total,
                      keyword_init: true)
  Prediction = Struct.new(:label, :ranking, :scores, :posterior, :score, :margin, :normalizer,
                          keyword_init: true)

  def self.count(documents, encoded, class_count, vocabulary_size)
    class_counts = Array.new(class_count, 0)
    n = Array.new(class_count) { Array.new(vocabulary_size, 0) }
    d = Array.new(class_count) { Array.new(vocabulary_size, 0) }
    documents.each_with_index do |document, index|
      class_id = document.class_id
      class_counts[class_id] += 1
      encoded[index].unique.each do |term|
        n[class_id][term] += encoded[index].counts.fetch(term)
        d[class_id][term] += 1
      end
    end
    totals = n.map(&:sum)
    term_totals = Array.new(vocabulary_size) { |term| n.sum { |row| row[term] } }
    df = Array.new(vocabulary_size) { |term| d.sum { |row| row[term] } }
    Counts.new(documents: documents.length, class_counts: class_counts, n: n, d: d,
               totals: totals, term_totals: term_totals, df: df, total: totals.sum)
  end

  def self.train(kind, counts, alpha)
    class_count = counts.class_counts.length
    size = counts.term_totals.length
    weights = Array.new(class_count) { Array.new(size) }
    priors = counts.class_counts.map { |number| Math.log(number.fdiv(counts.documents)) }
    bases = Array.new(class_count, 0.0)
    class_count.times do |class_id|
      size.times do |term|
        case kind
        when 'multinomial'
          numerator = 100 * counts.n[class_id][term] + alpha
          denominator = 100 * counts.totals[class_id] + alpha * size
          weights[class_id][term] = Math.log(numerator.fdiv(denominator))
        when 'bernoulli'
          denominator = 100 * counts.class_counts[class_id] + 2 * alpha
          present = 100 * counts.d[class_id][term] + alpha
          absent = 100 * (counts.class_counts[class_id] - counts.d[class_id][term]) + alpha
          log_p = Math.log(present.fdiv(denominator))
          log_q = Math.log(absent.fdiv(denominator))
          weights[class_id][term] = log_p - log_q
          bases[class_id] += log_q
        when 'complement'
          numerator = 100 * (counts.term_totals[term] - counts.n[class_id][term]) + alpha
          denominator = 100 * (counts.total - counts.totals[class_id]) + alpha * size
          weights[class_id][term] = Math.log(numerator.fdiv(denominator))
        end
      end
    end
    Model.new(kind, weights, priors, bases)
  end

  def self.normalize(scores)
    ranking = scores.each_index.sort_by { |class_id| [-scores[class_id], class_id] }
    label = ranking.first
    exponentials = scores.map { |score| Math.exp(score - scores[label]) }
    normalizer = 0.0
    exponentials.each { |value| normalizer += value }
    posterior = exponentials.map { |value| value / normalizer }
    Prediction.new(label: label, ranking: ranking, scores: scores, posterior: posterior,
                   score: posterior[label], margin: scores[label] - scores[ranking[1]], normalizer: normalizer)
  end

  class Model
    attr_reader :kind, :weights, :priors

    def initialize(kind, weights, priors, bases = nil)
      @kind = kind
      @weights = weights
      @priors = priors
      @bases = bases || Array.new(priors.length, 0.0)
    end

    def predict(document)
      scores = @priors.each_index.map do |class_id|
        if @kind == 'bernoulli'
          score = @bases[class_id]
          document.unique.each { |term| score += @weights[class_id][term] }
        else
          score = 0.0
          if @kind == 'complement'
            document.sequence.each { |term| score -= @weights[class_id][term] }
          else
            document.sequence.each { |term| score += @weights[class_id][term] }
          end
        end
        score + @priors[class_id]
      end
      NaiveBayes.normalize(scores)
    end
  end
end
