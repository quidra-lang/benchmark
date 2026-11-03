# Read the inputs and keep sparse rating tables in ascending ID order.
class Ratings
  attr_reader :training, :test, :titles, :genre_text, :genres, :params,
              :users, :items, :by_user, :by_item, :user_counts, :item_counts,
              :user_means, :item_means, :mean

  def initialize(training, test, titles, genre_text, params)
    @training, @test, @titles, @genre_text, @params = training, test, titles, genre_text, params
    @genres = genre_text.transform_values { |text| text.split('|') }
    users = Hash.new { |hash, key| hash[key] = {} }
    items = Hash.new { |hash, key| hash[key] = {} }
    training.each do |user, item, rating, _time|
      users[user][item] = rating
      items[item][user] = rating
    end
    @users = users.keys.sort
    @items = items.keys.sort
    @by_user = @users.to_h { |user| [user, users[user].sort.to_h] }
    @by_item = @items.to_h { |item| [item, items[item].sort.to_h] }
    @user_counts = @by_user.transform_values(&:size)
    @item_counts = @by_item.transform_values(&:size)
    @user_means = @by_user.to_h do |user, ratings|
      [user, ratings.values.sum.to_f / @user_counts[user]]
    end
    @item_means = @by_item.to_h do |item, ratings|
      [item, ratings.values.sum.to_f / @item_counts[item]]
    end
    @mean = training.sum { |row| row[2] }.to_f / training.size
  end

  def self.integer_rows(path)
    File.readlines(path, chomp: true).drop(1).map { |line| line.split(',').map(&:to_i) }
  end

  def self.read(directory = 'input')
    training = integer_rows(File.join(directory, 'ratings.csv'))
    test = integer_rows(File.join(directory, 'test.csv'))
    titles = {}
    genre_text = {}
    File.readlines(File.join(directory, 'items.csv'), chomp: true).drop(1).each do |line|
      item, title, genres = line.split(',')
      titles[item.to_i] = title
      genre_text[item.to_i] = genres
    end
    real_keys = %w[MIN_SIMILARITY BIAS_REG LEARNING_RATE REGULARIZATION ALS_REG]
    list_keys = %w[BIAS_REG CUTOFFS NEIGHBOR_GRID USER_GROUPS ITEM_GROUPS RECOMMEND_USERS SIMILAR_ITEMS]
    params = {}
    File.foreach(File.join(directory, 'params.txt'), chomp: true) do |line|
      key, *values = line.split(' ')
      values.map! { |value| real_keys.include?(key) ? value.to_f : value.to_i }
      params[key.downcase.to_sym] = list_keys.include?(key) ? values : values.first
    end
    new(training, test, titles, genre_text, params)
  end
end
