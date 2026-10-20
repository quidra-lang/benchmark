class Evaluation
  attr_reader :matrix, :correct, :total, :micro, :macro

  def self.real(value)
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def self.rounded_key(value)
    real(value).delete('.').to_i
  end

  def self.two(hundredfold)
    "#{hundredfold / 100}.#{(hundredfold % 100).to_s.rjust(2, '0')}"
  end

  def self.proportion(numerator, denominator)
    "#{numerator}/#{denominator} #{real(numerator.fdiv(denominator))}"
  end

  def self.fraction(numerator, denominator)
    return '- -' if denominator.zero?

    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor} #{real(numerator.fdiv(denominator))}"
  end

  def initialize(truth, predictions, class_count)
    @matrix = Array.new(class_count) { Array.new(class_count, 0) }
    truth.each_with_index { |actual, index| @matrix[actual][predictions[index]] += 1 }
    @total = truth.length
    @correct = class_count.times.sum { |class_id| @matrix[class_id][class_id] }
    @micro = @correct.fdiv(@total)
    @statistics = class_count.times.map do |class_id|
      [@matrix[class_id][class_id], @matrix.sum { |row| row[class_id] }, @matrix[class_id].sum]
    end
    sum = 0.0
    included = 0
    @statistics.each do |tp, predicted, actual|
      next if predicted + actual == 0

      sum += (2 * tp).fdiv(predicted + actual)
      included += 1
    end
    @macro = sum / included
  end

  def lines(classes)
    result = ["true\\predicted #{classes.join(' ')}"]
    classes.each_with_index { |name, class_id| result << "#{name} #{@matrix[class_id].join(' ')}" }
    classes.each_with_index do |name, class_id|
      tp, predicted, actual = @statistics[class_id]
      result << "class #{name} precision #{self.class.fraction(tp, predicted)} " \
                "recall #{self.class.fraction(tp, actual)} f1 #{self.class.fraction(2 * tp, predicted + actual)} support #{actual}"
    end
    result << "micro_f1 #{self.class.real(@micro)} macro_f1 #{self.class.real(@macro)}"
    result
  end
end
