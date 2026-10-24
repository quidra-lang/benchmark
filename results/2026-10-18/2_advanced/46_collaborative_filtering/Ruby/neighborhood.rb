# Symmetric similarities and oriented integer Slope One differences.
class Neighborhood
  attr_reader :user, :item, :counts

  def self.largest(candidates, size)
    candidates.sort_by { |id, similarity| [-similarity, id] }.first(size)
  end

  def initialize(data, shrinkage)
    @user, @item, @counts, @differences = {}, {}, {}, {}
    @shrinkage = shrinkage
    build_users(data)
    build_items(data)
  end

  def pair(first, second)
    first < second ? [first, second] : [second, first]
  end

  def user_similarity(user, other)
    @user[pair(user, other)]
  end

  def item_similarity(item, other)
    @item[pair(item, other)]
  end

  def common_count(item, other)
    @counts.fetch(pair(item, other), 0)
  end

  def difference(target, source)
    value = @differences.fetch(pair(target, source), 0)
    target < source ? value : -value
  end

  def deviation(target, source)
    difference(target, source).to_f / (common_count(target, source) + @shrinkage)
  end

  private

  def build_users(data)
    data.users.combination(2) do |user, other|
      left, right = data.by_user[user], data.by_user[other]
      common = left.keys.select { |item| right.key?(item) }
      count = common.size
      next if count < 2

      sx = sy = sxx = syy = sxy = 0
      common.each do |item|
        x, y = left[item], right[item]
        sx += x
        sy += y
        sxx += x * x
        syy += y * y
        sxy += x * y
      end
      numerator = count * sxy - sx * sy
      dx = count * sxx - sx * sx
      dy = count * syy - sy * sy
      next if dx.zero? || dy.zero?

      a = (numerator * count) * (numerator * count)
      b = dx * dy * (count + @shrinkage) * (count + @shrinkage)
      sign = numerator <=> 0
      @user[[user, other]] = [sign * Math.sqrt(a.to_f / b), count]
    end
  end

  def build_items(data)
    data.items.combination(2) do |item, other|
      left, right = data.by_item[item], data.by_item[other]
      common = left.keys.select { |user| right.key?(user) }
      count = common.size
      next if count.zero?

      @counts[[item, other]] = count
      @differences[[item, other]] = common.sum { |user| left[user] - right[user] }
      next if count < 2

      numerator = left_norm = right_norm = 0.0
      common.each do |user|
        x = left[user] - data.user_means[user]
        y = right[user] - data.user_means[user]
        numerator += x * y
        left_norm += x * x
        right_norm += y * y
      end
      next if left_norm.zero? || right_norm.zero?

      similarity = numerator / Math.sqrt(left_norm * right_norm) * count / (count + @shrinkage)
      @item[[item, other]] = [similarity, count]
    end
  end
end
