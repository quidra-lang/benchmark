class Vocabulary
  Entry = Struct.new(:term, :df, :chi_square, :best_class)
  Encoded = Struct.new(:sequence, :unique, :counts)
  attr_reader :terms, :ranking, :candidate_count, :all_term_count, :df, :class_counts, :positions

  def initialize(documents, class_count, minimum_df, features, use_bigrams)
    @use_bigrams = use_bigrams
    @class_counts = Array.new(class_count, 0)
    occurrences = Hash.new { |hash, term| hash[term] = Array.new(class_count, 0) }
    documents.each do |document|
      @class_counts[document.class_id] += 1
      document.terms(use_bigrams).uniq.each { |term| occurrences[term][document.class_id] += 1 }
    end
    @df = occurrences.transform_values(&:sum)
    @all_term_count = occurrences.length
    count = documents.length
    candidates = []
    occurrences.each do |term, per_class|
      frequency = @df.fetch(term)
      next if frequency < minimum_df

      best_value = 0.0
      best_class = 0
      class_count.times do |class_id|
        a = per_class[class_id]
        b = frequency - a
        c = @class_counts[class_id] - a
        e = count - @class_counts[class_id] - b
        difference = a * e - b * c
        numerator = count * difference * difference
        denominator = frequency * (count - frequency) * @class_counts[class_id] *
                      (count - @class_counts[class_id])
        value = denominator.zero? ? 0.0 : numerator.fdiv(denominator)
        if value > best_value
          best_value = value
          best_class = class_id
        end
      end
      candidates << Entry.new(term, frequency, best_value, best_class)
    end
    @candidate_count = candidates.length
    candidates.sort_by! { |entry| [-entry.chi_square, entry.term] }
    @ranking = features.positive? ? candidates.first(features) : candidates
    @terms = @ranking.map(&:term).sort
    @positions = @terms.each_with_index.to_h
  end

  def size
    @terms.length
  end

  def encode(document)
    sequence = document.terms(@use_bigrams).filter_map { |term| @positions[term] }
    counts = sequence.tally
    Encoded.new(sequence, counts.keys, counts)
  end
end
