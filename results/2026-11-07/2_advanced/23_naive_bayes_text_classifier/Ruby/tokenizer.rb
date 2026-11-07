module Tokenizer
  Document = Struct.new(:id, :label, :class_id, :number, :words, :bigrams,
                        :raw_count, :stop_count, :short_count, keyword_init: true) do
    def terms(use_bigrams)
      use_bigrams ? (@combined ||= words + bigrams) : words
    end
  end

  def self.document(text, stopwords, id: nil, label: nil, number: nil)
    raw = text.scan(/[A-Za-z0-9]+/).map(&:downcase)
    words = []
    stops = shorts = 0
    raw.each do |word|
      if stopwords.include?(word)
        stops += 1
      elsif word.length == 1
        shorts += 1
      else
        words << word
      end
    end
    bigrams = words.each_cons(2).map { |left, right| "#{left}_#{right}" }
    Document.new(id: id, label: label, number: number, words: words, bigrams: bigrams,
                 raw_count: raw.length, stop_count: stops, short_count: shorts)
  end
end
