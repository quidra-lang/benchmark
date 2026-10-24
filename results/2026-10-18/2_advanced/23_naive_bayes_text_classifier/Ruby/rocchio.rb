class Rocchio
  Prediction = Struct.new(:label, :ranking, :scores, :score, keyword_init: true)

  def initialize(documents, encoded, vocabulary, class_count)
    @idf = vocabulary.terms.map { |term| Math.log(documents.length.fdiv(vocabulary.df.fetch(term))) }
    @centroids = Array.new(class_count) { Array.new(vocabulary.size, 0.0) }
    documents.each_with_index do |document, index|
      components, length = vector(encoded[index])
      next if length.zero?

      components.each do |term, value|
        @centroids[document.class_id][term] += value / length
      end
    end
    @lengths = @centroids.each_with_index.map do |centroid, class_id|
      squared = 0.0
      centroid.each_index do |term|
        centroid[term] /= vocabulary.class_counts[class_id]
        squared += centroid[term] * centroid[term]
      end
      Math.sqrt(squared)
    end
  end

  def vector(document)
    squared = 0.0
    components = []
    document.unique.sort.each do |term|
      value = document.counts.fetch(term) * @idf[term]
      next if value.zero?

      components << [term, value]
      squared += value * value
    end
    [components, Math.sqrt(squared)]
  end

  def predict(document)
    components, length = vector(document)
    scores = @centroids.each_with_index.map do |centroid, class_id|
      if length.positive? && @lengths[class_id].positive?
        product = 0.0
        components.each { |term, value| product += value * centroid[term] }
        product / (length * @lengths[class_id])
      else
        0.0
      end
    end
    ranking = scores.each_index.sort_by { |class_id| [-scores[class_id], class_id] }
    Prediction.new(label: ranking.first, ranking: ranking, scores: scores, score: scores[ranking.first])
  end
end
