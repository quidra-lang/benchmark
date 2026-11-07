module Dataset
  Row = Data.define(:id, :values, :label)

  def self.read_csv(path)
    lines = File.readlines(path, chomp: true)
    names = lines.shift.split(',')[1...-1]
    rows = lines.map do |line|
      fields = line.split(',')
      Row.new(fields[0], fields[1...-1].map(&:to_f), fields[-1].to_i)
    end
    [names, rows]
  end

  def self.read
    names, training = read_csv('input/train.csv')
    _test_names, test = read_csv('input/test.csv')
    words = File.readlines('input/params.txt', chomp: true).map(&:split)
    settings = {
      positive: words[0][1].to_i,
      degree: words[1][1].to_i,
      threshold: words[2][1].to_f,
      lambdas: words[3].drop(1).map(&:to_f),
      gd: [words[4][1].to_f, words[4][2].to_i],
      sgd: [words[5][1].to_f, *words[5].drop(2).map(&:to_i)],
      softmax: [words[6][1].to_f, words[6][2].to_i, words[6][3].to_f],
      bootstrap: words[7].drop(1).map(&:to_i),
      permutation: words[8].drop(1).map(&:to_i),
      map: words[9].drop(1).map(&:to_i),
      cost: words[10].drop(1).map(&:to_i)
    }
    [names, training, test, settings]
  end

  def self.tuples(dimension, degree)
    indices = (0...dimension).to_a
    (1..degree).flat_map { |size| indices.repeated_combination(size).to_a }
  end

  def self.expand(values, tuples)
    tuples.map do |tuple|
      product = values[tuple[0]]
      tuple.drop(1).each { |index| product *= values[index] }
      product
    end
  end

  def self.statistics(rows, count = rows[0].length)
    means = Array.new(count) do |feature|
      total = 0.0
      rows.each { |row| total += row[feature] }
      total / rows.length.to_f
    end
    deviations = Array.new(count) do |feature|
      total = 0.0
      rows.each do |row|
        difference = row[feature] - means[feature]
        total += difference * difference
      end
      Math.sqrt(total / (rows.length - 1).to_f)
    end
    [means, deviations]
  end

  def self.standardize(rows, means, deviations)
    rows.map do |row|
      [1.0] + means.each_index.map { |index| (row[index] - means[index]) / deviations[index] }
    end
  end
end
