# frozen_string_literal: true

module Dataset
  Row = Struct.new(:id, :features, :label, :target)

  def self.rows(path)
    lines = File.readlines(path, chomp: true)
    features = lines.first.split(',')[1...-2]
    rows = lines.drop(1).map do |line|
      fields = line.split(',', -1)
      Row.new(fields.first, fields[1...-2].map(&:to_f), fields[-2].empty? ? nil : fields[-2],
              fields[-1].empty? ? nil : fields[-1].to_f)
    end
    [features, rows]
  end

  def self.read
    features, training = rows('input/train.csv')
    _, testing = rows('input/test.csv')
    parameters = File.readlines('input/params.txt', chomp: true).to_h do |line|
      name, *values = line.split(' ')
      [name, values]
    end
    settings = { scalings: parameters['SCALINGS'], k_values: parameters['K_VALUES'].map(&:to_i),
                 metrics: parameters['METRICS'], weightings: parameters['WEIGHTINGS'],
                 folds: parameters['FOLDS'].first.to_i, edit_k: parameters['EDIT_K'].first.to_i,
                 curve: parameters['CURVE'].map(&:to_i), bins: parameters['BINS'].map(&:to_f),
                 top: parameters['TOP'].first.to_i }
    [features, training, testing, settings]
  end
end
