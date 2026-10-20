# frozen_string_literal: true

module Features
  NAMES = %w[recency frequency monetary basket categories tenure].freeze
  SQUARE_ROOT = [1, 2, 3].freeze
  Customer = Struct.new(:id, :raw, :spend, :category_spend, :orders, :transformed, :point, keyword_init: true)

  def self.customers(day, orders)
    grouped = orders.select { |order| order.net.positive? }.group_by(&:customer)
    grouped.keys.sort.map do |id|
      purchases = grouped.fetch(id)
      spend = purchases.sum(&:net)
      categories = Hash.new(0)
      purchases.each { |order| order.rows.each { |row| categories[row.category] += row.amount } }
      days = purchases.map(&:day)
      frequency = purchases.length
      monetary = spend / 100.0
      raw = [day - days.max, frequency, monetary, monetary / frequency,
             categories.count { |_, amount| amount.positive? }, day - days.min]
      Customer.new(id: id, raw: raw, spend: spend, category_spend: categories, orders: purchases,
                   transformed: transform(raw))
    end
  end

  def self.transform(values)
    values.each_with_index.map { |value, index| SQUARE_ROOT.include?(index) ? Math.sqrt(value) : value.to_f }
  end

  def self.mean_sd(values)
    mean = values.reduce(0.0) { |sum, value| sum + value } / values.length
    variance = values.reduce(0.0) { |sum, value| sum + (value - mean) * (value - mean) } / (values.length - 1)
    [mean, Math.sqrt(variance)]
  end

  def self.standardize(values, means, deviations)
    values.each_index.map { |index| deviations[index].zero? ? 0.0 : (values[index] - means[index]) / deviations[index] }
  end

  def self.scale(customers)
    raw = NAMES.each_index.map { |index| mean_sd(customers.map { |customer| customer.raw[index] }) }
    transformed = NAMES.each_index.map { |index| mean_sd(customers.map { |customer| customer.transformed[index] }) }
    means = transformed.map(&:first)
    deviations = transformed.map(&:last)
    customers.each { |customer| customer.point = standardize(customer.transformed, means, deviations) }
    { raw_mean: raw.map(&:first), raw_sd: raw.map(&:last), mean: means, sd: deviations }
  end

  def self.correlation(points)
    NAMES.each_index.map do |first|
      NAMES.each_index.map do |last|
        points.reduce(0.0) { |sum, point| sum + point[first] * point[last] } / (points.length - 1)
      end
    end
  end
end
