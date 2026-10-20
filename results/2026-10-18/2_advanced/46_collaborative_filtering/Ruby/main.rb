require 'set'
require_relative 'ratings'
require_relative 'neighborhood'
require_relative 'factorization'
require_relative 'evaluation'
require_relative 'report'

METHODS = %w[GLOBAL BASELINE USER_KNN ITEM_KNN SLOPE_ONE SVD ALS].freeze
RANKINGS = ['POPULAR', *METHODS.drop(1)].freeze
KNN_METHODS = %w[USER_KNN ITEM_KNN].freeze
Prediction = Struct.new(:value, :fallback, :neighbors, :similarity, :top)

# Coordinate training, predictions, analyses, ranked lists, and all five reports.
class Recommender
  include Evaluation
  include Report

  def initialize(data)
    @data, @params = data, data.params
    @neighborhood = Neighborhood.new(data, @params[:shrinkage])
    @user_bias = data.users.to_h { |user| [user, 0.0] }
    @item_bias = data.items.to_h { |item| [item, 0.0] }
    @popularity = data.items.sort_by { |item| [-data.item_counts[item], -data.item_means[item], item] }
    @head = data.items.size / 5
    @popular_items = @popularity.first(@head).to_set
    @log, @train_errors, @metrics = [], {}, {}
    @predictions = METHODS.to_h { |method| [method, []] }
    @clipped = METHODS.to_h { |method| [method, []] }
    @errors = METHODS.to_h { |method| [method, []] }
    @relevant, @rankings, @ranking_predictions = {}, {}, {}
  end

  def baseline(user, item)
    (@data.mean + @user_bias[user]) + @item_bias[item]
  end

  def train
    item_reg, user_reg = @params[:bias_reg]
    @train_errors['GLOBAL'] = training_rmse(@data.training) { @data.mean }
    1.upto(10) do |sweep|
      @data.items.each do |item|
        total = 0.0
        @data.by_item[item].each do |user, rating|
          total += rating - @data.mean - @user_bias[user]
        end
        @item_bias[item] = total / (item_reg + @data.item_counts[item])
      end
      @data.users.each do |user|
        total = 0.0
        @data.by_user[user].each do |item, rating|
          total += rating - @data.mean - @item_bias[item]
        end
        @user_bias[user] = total / (user_reg + @data.user_counts[user])
      end
      @log << ['BASELINE', sweep, training_rmse(@data.training, &method(:baseline))]
    end
    @train_errors['BASELINE'] = @log.last[2]
    @svd, log = Factorization.train_svd(@data)
    @log.concat(log)
    @train_errors['SVD'] = log.last[2]
    @als, log = Factorization.train_als(@data, @user_bias, @item_bias)
    @log.concat(log)
    @train_errors['ALS'] = log.last[2]
  end

  def neighbor_prediction(user, item, method, size)
    user_based = method == 'USER_KNN'
    entries = user_based ? @data.by_item[item] : @data.by_user[user]
    means = user_based ? @data.user_means : @data.item_means
    candidates = []
    entries.each_key do |other|
      similarity = if user_based
                     @neighborhood.user_similarity(user, other)
                   else
                     @neighborhood.item_similarity(item, other)
                   end
      candidates << [other, similarity[0]] if similarity && similarity[0] > @params[:min_similarity]
    end
    selected = Neighborhood.largest(candidates, size)
    return Prediction.new(baseline(user, item), true) if selected.empty?

    numerator = denominator = 0.0
    selected.each do |other, similarity|
      numerator += similarity * (entries[other] - means[other])
      denominator += similarity
    end
    mean = user_based ? @data.user_means[user] : @data.item_means[item]
    Prediction.new(mean + numerator / denominator, false, selected.size,
                   denominator / selected.size, selected.first[0])
  end

  def slope_prediction(user, item)
    numerator = 0.0
    denominator = 0
    @data.by_user[user].each do |other, rating|
      count = @neighborhood.common_count(item, other)
      next if count.zero?

      numerator += (@neighborhood.deviation(item, other) + rating) * count
      denominator += count
    end
    return Prediction.new(baseline(user, item), true) if denominator.zero?

    Prediction.new(numerator / denominator)
  end

  def predict(method, user, item, size = @params[:neighbors])
    case method
    when 'GLOBAL' then Prediction.new(@data.mean)
    when 'BASELINE' then Prediction.new(baseline(user, item))
    when 'USER_KNN', 'ITEM_KNN' then neighbor_prediction(user, item, method, size)
    when 'SLOPE_ONE' then slope_prediction(user, item)
    when 'SVD' then Prediction.new(@svd.predict(user, item))
    when 'ALS' then Prediction.new(@als.predict(user, item))
    else raise ArgumentError, "Unknown prediction method: #{method}"
    end
  end

  def predict_tests
    lines = ['user,item,actual,' + METHODS.join(',')]
    @data.test.each do |user, item, actual|
      fields = [user, item, actual]
      METHODS.each do |method|
        prediction = predict(method, user, item)
        clipped = clip(prediction.value)
        @predictions[method] << prediction
        @clipped[method] << clipped
        @errors[method] << clipped - actual
        fields << real(clipped)
      end
      lines << fields.join(',')
    end
    METHODS.each do |method|
      predictions = @predictions[method]
      @metrics[method] = [rmse(@errors[method]), mae(@errors[method]),
                          predictions.count { |p| p.value < 1 || p.value > 5 },
                          predictions.count(&:fallback)]
    end
    lines
  end

  def prepare_rankings
    relevant = Hash.new { |hash, key| hash[key] = Set.new }
    @data.test.each { |user, item, rating| relevant[user] << item if rating >= 4 }
    @relevant = relevant.sort.to_h
    requested = @params[:recommend_users].select { |user| @data.by_user.key?(user) }
    (@relevant.keys | requested).sort.each do |user|
      rated = @data.by_user[user]
      candidates = @data.items.reject { |item| rated.key?(item) }
      lists = { 'POPULAR' => @popularity.reject { |item| rated.key?(item) } }
      predictions = {}
      METHODS.drop(1).each do |method|
        values = candidates.to_h { |item| [item, predict(method, user, item)] }
        predictions[method] = values
        lists[method] = candidates.sort_by { |item| [-values[item].value, item] }
      end
      @rankings[user] = lists
      @ranking_predictions[user] = predictions
    end
  end

  def separate_sections(sections)
    sections.each_with_index.flat_map { |section, index| index.zero? ? section : ['', *section] }
  end

  def count_summary(counts)
    ordered = counts.sort
    middle = ordered.size / 2
    median = ordered.size.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
    "min #{ordered.first} median #{real(median)} max #{ordered.last}"
  end

  def data_summary
    histogram = Array.new(5, 0)
    @data.training.each { |_, _, rating, _| histogram[rating - 1] += 1 }
    first, last = @data.training.map(&:last).minmax
    theta = @params[:min_similarity]
    user_usable = @neighborhood.user.count { |_, value| value[0] > theta }
    item_usable = @neighborhood.item.count { |_, value| value[0] > theta }
    [
      "data users #{@data.users.size} items #{@data.items.size} catalog #{@data.titles.size} " \
        "ratings #{@data.training.size} test #{@data.test.size}",
      "density #{real(@data.training.size.to_f / (@data.users.size * @data.items.size))} " \
        "global_mean #{real(@data.mean)}",
      'histogram ' + histogram.join(' '),
      'user_ratings ' + count_summary(@data.user_counts.values),
      'item_ratings ' + count_summary(@data.item_counts.values),
      "timestamps first #{first} last #{last}",
      "cold_items #{@data.titles.size - @data.items.size}",
      "similarities user_pairs #{@neighborhood.user.size} usable #{user_usable} " \
        "item_pairs #{@neighborhood.item.size} usable #{item_usable} slope_pairs #{@neighborhood.counts.size}"
    ]
  end

  def genre_summary
    genres = @data.items.flat_map { |item| @data.genres[item] }.uniq.sort
    lines = ['genre_stats']
    genres.each do |genre|
      items = @data.items.select { |item| @data.genres[item].include?(genre) }
      ratings = items.sum { |item| @data.item_counts[item] }
      high = items.sum { |item| @data.by_item[item].count { |_, rating| rating >= 4 } }
      lines << "genre #{genre} items #{items.size} ratings #{ratings} high #{high}"
    end
    lines
  end

  def time_summary
    buckets = @params[:time_buckets]
    counts, totals = Array.new(buckets, 0), Array.new(buckets, 0)
    users = Array.new(buckets) { Set.new }
    first, last = @data.training.map(&:last).minmax
    @data.training.each do |user, _, rating, timestamp|
      bucket = (timestamp - first) * buckets / (last - first + 1)
      counts[bucket] += 1
      totals[bucket] += rating
      users[bucket] << user
    end
    lines = ["time_buckets #{buckets}"]
    buckets.times do |bucket|
      count = counts[bucket]
      mean = count.zero? ? nil : totals[bucket].to_f / count
      lines << "bucket #{bucket + 1} ratings #{count} users #{users[bucket].size} mean #{real(mean)}"
    end
    lines
  end

  def rating_metrics
    lines = ['rating_metrics']
    METHODS.each do |method|
      error, absolute, clipped, fallback = @metrics[method]
      lines << "#{method} rmse #{real(error)} mae #{real(absolute)} clipped #{clipped} fallback #{fallback}"
    end
    lines
  end

  def generalization
    lines = ['generalization']
    %w[GLOBAL BASELINE SVD ALS].each do |method|
      train, test = @train_errors[method], @metrics[method][0]
      lines << "#{method} train #{real(train)} test #{real(test)} gap #{real(test - train)}"
    end
    lines
  end

  def neighborhood_usage
    lines = ["neighborhoods k #{@params[:neighbors]}"]
    KNN_METHODS.each do |method|
      used = @predictions[method].reject(&:fallback)
      count = used.size
      mean_count = count.zero? ? nil : used.sum(&:neighbors).to_f / count
      similarity = count.zero? ? nil : ordered_sum(used, &:similarity) / count
      lines << "#{method} predictions #{@data.test.size} with_neighbors #{count} " \
        "mean_neighbors #{real(mean_count)} mean_similarity #{real(similarity)}"
    end
    lines
  end

  def prediction_statistics
    actual = @data.test.map { |row| row[2] }
    count = actual.size
    actual_mean = actual.sum.to_f / count
    actual_variation = ordered_sum(actual) { |rating| (rating - actual_mean) * (rating - actual_mean) }
    lines = ["prediction_stats actual mean #{real(actual_mean)} std #{real(Math.sqrt(actual_variation / count))}"]
    METHODS.each do |method|
      values = @clipped[method]
      mean = ordered_sum(values) / count
      variation = ordered_sum(values) { |value| (value - mean) * (value - mean) }
      correlation = nil
      if values.min != values.max && actual.min != actual.max
        covariance = ordered_sum(values.each_index) do |index|
          (values[index] - mean) * (actual[index] - actual_mean)
        end
        correlation = covariance / Math.sqrt(variation * actual_variation)
      end
      lines << "#{method} mean #{real(mean)} std #{real(Math.sqrt(variation / count))} " \
        "correlation #{real(correlation)}"
    end
    lines
  end

  def error_bins
    lines = ['error_bins edges 0.5 1.0 1.5 2.0']
    METHODS.each do |method|
      bins = Array.new(5, 0)
      @errors[method].each do |error|
        bin = [0.5, 1.0, 1.5, 2.0].count { |edge| error.abs >= edge }
        bins[bin] += 1
      end
      lines << method + ' ' + bins.join(' ')
    end
    lines
  end

  def comparison
    lines = ['comparison']
    METHODS.combination(2) do |first, second|
      wins = ties = losses = 0
      @errors[first].zip(@errors[second]).each do |left, right|
        if left.abs < right.abs
          wins += 1
        elsif left.abs == right.abs
          ties += 1
        else
          losses += 1
        end
      end
      lines << "#{first} #{second} wins #{wins} ties #{ties} losses #{losses}"
    end
    lines
  end

  def errors_for(indices, metric = :rmse)
    METHODS.map do |method|
      values = indices.map { |index| @errors[method][index] }
      "#{method} #{real(send(metric, values))}"
    end.join(' ')
  end

  def group_number(count, bounds)
    bounds.count { |bound| count >= bound }
  end

  def group_errors(kind)
    bounds = @params["#{kind}_groups".to_sym]
    counts = kind == 'user' ? @data.user_counts : @data.item_counts
    field = kind == 'user' ? 0 : 1
    groups = Array.new(bounds.size + 1) { [] }
    @data.test.each_with_index { |row, index| groups[group_number(counts[row[field]], bounds)] << index }
    lines = ["#{kind}_groups bounds " + bounds.join(' ')]
    groups.each_with_index do |indices, number|
      lower = number.zero? ? 1 : bounds[number - 1]
      upper = number < bounds.size ? bounds[number] - 1 : nil
      lines << "group #{number + 1} from #{lower} to #{optional(upper)} pairs #{indices.size} " + errors_for(indices)
    end
    lines
  end

  def rating_errors
    lines = ['by_rating']
    1.upto(5) do |rating|
      indices = @data.test.each_index.select { |index| @data.test[index][2] == rating }
      lines << "rating #{rating} pairs #{indices.size} " + errors_for(indices, :mae)
    end
    lines
  end

  def genre_errors
    genres = @data.test.flat_map { |_, item, _| @data.genres[item] }.uniq.sort
    lines = ['genres']
    genres.each do |genre|
      indices = @data.test.each_index.select { |index| @data.genres[@data.test[index][1]].include?(genre) }
      lines << "genre #{genre} pairs #{indices.size} " + errors_for(indices)
    end
    lines
  end

  def user_ranking_metrics(method, user, cutoff)
    ranking_metrics(@rankings[user][method], @relevant[user], cutoff)
  end

  def ranking_evaluation
    count = @relevant.size
    relevant_count = @relevant.values.sum(&:size)
    lines = ["ranking users #{count} relevant #{relevant_count}"]
    @params[:cutoffs].each do |cutoff|
      lines << "cutoff #{cutoff}"
      RANKINGS.each do |method|
        metrics = @relevant.keys.map { |user| user_ranking_metrics(method, user, cutoff) }
        precision = metrics.sum { |metric| metric[0] }.to_f / (cutoff * count)
        recall, ndcg, average_precision, reciprocal_rank = (1..4).map do |index|
          ordered_sum(metrics) { |metric| metric[index] } / count
        end
        hit_rate = metrics.count { |metric| metric[0] >= 1 }.to_f / count
        lines << "  #{method} precision #{real(precision)} recall #{real(recall)} " \
          "ndcg #{real(ndcg)} map #{real(average_precision)} mrr #{real(reciprocal_rank)} hit_rate #{real(hit_rate)}"
      end
    end
    lines
  end

  def beyond_accuracy
    size, count = @params[:top_n], @relevant.size
    pair_count = size * (size - 1) / 2
    lines = ["beyond_accuracy top_n #{size} head #{@head}"]
    RANKINGS.each do |method|
      distinct = Set.new
      diversity = popularity = long_tail = 0
      novelty = similarity = 0.0
      @relevant.each_key do |user|
        ranked = @rankings[user][method].first(size)
        distinct.merge(ranked)
        diversity += ranked.flat_map { |item| @data.genres[item] }.uniq.size
        novelty += ordered_sum(ranked) { |item| Math.log2(@data.users.size.to_f / @data.item_counts[item]) } / size
        popularity += ranked.sum { |item| @data.item_counts[item] }
        long_tail += ranked.count { |item| !@popular_items.include?(item) }
        pair_similarity = 0.0
        ranked.combination(2) do |first, second|
          value = @neighborhood.item_similarity(first, second)
          pair_similarity += (value ? value[0] : 0.0)
        end
        similarity += pair_similarity / pair_count
      end
      lines << "#{method} coverage #{real(distinct.size.to_f / @data.items.size)} " \
        "diversity #{real(diversity.to_f / count)} novelty #{real(novelty / count)} " \
        "popularity #{real(popularity.to_f / (size * count))} " \
        "long_tail #{real(long_tail.to_f / (size * count))} similarity #{real(similarity / count)}"
    end
    lines
  end

  def ranking_groups
    size, bounds = @params.values_at(:top_n, :user_groups)
    groups = Array.new(bounds.size + 1) { [] }
    @relevant.each_key { |user| groups[group_number(@data.user_counts[user], bounds)] << user }
    lines = ["ranking_groups top_n #{size} bounds " + bounds.join(' ')]
    groups.each_with_index do |users, number|
      fields = ["group #{number + 1} users #{users.size}"]
      RANKINGS.each do |method|
        mean = if users.empty?
                 nil
               else
                 ordered_sum(users) { |user| user_ranking_metrics(method, user, size)[2] } / users.size
               end
        fields << "#{method} #{real(mean)}"
      end
      lines << fields.join(' ')
    end
    lines
  end

  def agreement
    size = @params[:top_n]
    lines = ["agreement top_n #{size}"]
    RANKINGS.combination(2) do |first, second|
      total = 0.0
      @relevant.each_key do |user|
        left = @rankings[user][first].first(size).to_set
        right = @rankings[user][second].first(size).to_set
        total += (left & right).size.to_f / (left | right).size
      end
      lines << "#{first} #{second} jaccard #{real(total / @relevant.size)}"
    end
    lines
  end

  def neighbor_grid
    lines = ['neighbor_grid']
    errors = KNN_METHODS.to_h { |method| [method, {}] }
    @params[:neighbor_grid].each do |size|
      fields = ["k #{size}"]
      KNN_METHODS.each do |method|
        residuals = @data.test.map do |user, item, actual|
          clip(predict(method, user, item, size).value) - actual
        end
        error = rmse(residuals)
        errors[method][size] = error
        fields << "#{method} #{real(error)}"
      end
      lines << fields.join(' ')
    end
    fields = ['best']
    KNN_METHODS.each do |method|
      best = errors[method].keys.min_by { |size| [errors[method][size], size] }
      fields << "#{method} #{best}"
    end
    lines << fields.join(' ')
  end

  def bias_lists
    lines = ['biases']
    tables = [
      ['item', @data.items, @item_bias, @data.item_counts, @data.item_means],
      ['user', @data.users, @user_bias, @data.user_counts, @data.user_means]
    ]
    tables.each do |kind, ids, biases, counts, means|
      [['high', -1], ['low', 1]].each do |label, sign|
        ids.sort_by { |id| [sign * biases[id], id] }.first(@params[:list_size]).each do |id|
          line = "#{kind}_#{label} #{id} bias #{real(biases[id])} count #{counts[id]} mean #{real(means[id])}"
          line += ' ' + @data.titles[id] if kind == 'item'
          lines << line
        end
      end
    end
    lines
  end

  def evaluation_report
    separate_sections([
      data_summary, genre_summary, time_summary, rating_metrics, generalization,
      neighborhood_usage, prediction_statistics, error_bins, comparison,
      group_errors('user'), group_errors('item'), rating_errors, genre_errors,
      ranking_evaluation, beyond_accuracy, ranking_groups, agreement, neighbor_grid, bias_lists
    ])
  end

  def preferred_genres(user, liked)
    counts = Hash.new(0)
    @data.by_user[user].each do |item, rating|
      next unless (liked ? rating >= 4 : rating <= 2)

      @data.genres[item].each { |genre| counts[genre] += 1 }
    end
    counts.sort_by { |genre, count| [-count, genre] }.first(3)
  end

  def popularity_line(rank, item)
    "  #{rank} #{item} count #{@data.item_counts[item]} " \
      "mean #{real(@data.item_means[item])} #{@data.titles[item]}"
  end

  def recommendation_line(user, method, rank, item)
    return popularity_line(rank, item) if method == 'POPULAR'

    prediction = @ranking_predictions[user][method][item]
    line = "  #{rank} #{item} #{real(prediction.value)}"
    line += ' via ' + optional(prediction.top) if KNN_METHODS.include?(method)
    line + ' ' + @data.titles[item]
  end

  def known_user_recommendations(user)
    size = @params[:top_n]
    lines = ["user #{user} ratings #{@data.user_counts[user]} mean #{real(@data.user_means[user])} " \
             "bias #{real(@user_bias[user])}"]
    liked, disliked = preferred_genres(user, true), preferred_genres(user, false)
    [['liked_genres', liked], ['disliked_genres', disliked]].each do |label, genres|
      entries = genres.map { |genre, count| "#{genre} #{count}" }.join(' ')
      lines << label + ' ' + (entries.empty? ? '-' : entries)
    end
    recent = @data.training.select { |row| row[0] == user }.sort_by { |row| [-row[3], row[1]] }.first(3)
    lines << 'recent ' + recent.map { |_, item, rating, _| "#{item} #{rating}" }.join(' ')
    candidates = []
    @data.users.each do |other|
      similarity = @neighborhood.user_similarity(user, other)
      candidates << [other, similarity[0]] if similarity && similarity[0] > @params[:min_similarity]
    end
    Neighborhood.largest(candidates, @params[:list_size]).each do |other, similarity|
      common = @neighborhood.user_similarity(user, other)[1]
      lines << "neighbor #{other} similarity #{real(similarity)} common #{common}"
    end
    @data.test.each_with_index do |(held_user, item, rating), index|
      next unless held_user == user

      values = METHODS.map { |method| real(@clipped[method][index]) }.join(' ')
      lines << "heldout #{item} actual #{rating} #{values}"
    end
    liked_names = liked.map(&:first)
    RANKINGS.each do |method|
      ranked = @rankings[user][method].first(size)
      matched = ranked.count { |item| @data.genres[item].any? { |genre| liked_names.include?(genre) } }
      lines << "list #{method} genre_match #{matched}"
      ranked.each_with_index { |item, index| lines << recommendation_line(user, method, index + 1, item) }
    end
    lines
  end

  def recommendations
    sections = @params[:recommend_users].map do |user|
      if @data.by_user.key?(user)
        known_user_recommendations(user)
      else
        lines = ["user #{user} unknown", 'list POPULAR']
        @popularity.first(@params[:top_n]).each_with_index do |item, index|
          lines << popularity_line(index + 1, item)
        end
        lines
      end
    end
    separate_sections(sections)
  end

  def similar_items
    size, factors = @params[:list_size], @svd.items
    norms = @data.items.to_h { |item| [item, Factorization.dot(factors[item], factors[item])] }
    sections = @params[:similar_items].map do |item|
      lines = ["item #{item} ratings #{@data.item_counts[item]} mean #{real(@data.item_means[item])} " \
               "bias #{real(@item_bias[item])} genres #{@data.genre_text[item]} title #{@data.titles[item]}",
               'cosine']
      candidates = @data.items.filter_map do |other|
        value = @neighborhood.item_similarity(item, other)
        [other, value[0]] if value
      end
      Neighborhood.largest(candidates, size).each_with_index do |(other, similarity), index|
        common = @neighborhood.item_similarity(item, other)[1]
        lines << "  #{index + 1} #{other} similarity #{real(similarity)} common #{common} #{@data.titles[other]}"
      end
      candidates = @data.items.reject { |other| other == item }.map do |other|
        cosine = Factorization.dot(factors[item], factors[other]) / Math.sqrt(norms[item] * norms[other])
        [other, cosine]
      end
      lines << 'factors'
      Neighborhood.largest(candidates, size).each_with_index do |(other, similarity), index|
        lines << "  #{index + 1} #{other} similarity #{real(similarity)} #{@data.titles[other]}"
      end
      common_items = @data.items.select { |other| @neighborhood.common_count(item, other) >= 1 }
      ordered = common_items.sort_by { |other| [-@neighborhood.common_count(item, other), other] }
      lines << 'co_rated'
      ordered.first(size).each_with_index do |other, index|
        common = @neighborhood.common_count(item, other)
        lines << "  #{index + 1} #{other} common #{common} #{@data.titles[other]}"
      end
      ordered = common_items.sort_by do |other|
        [-@neighborhood.deviation(other, item), -@neighborhood.common_count(other, item), other]
      end
      lines << 'slope_one'
      ordered.first(size).each_with_index do |other, index|
        difference = @neighborhood.difference(other, item)
        common = @neighborhood.common_count(other, item)
        lines << "  #{index + 1} #{other} difference #{difference} common #{common} #{@data.titles[other]}"
      end
      lines
    end
    separate_sections(sections)
  end

  def training_log
    ['method,epoch,train_rmse', *@log.map { |method, epoch, error| "#{method},#{epoch},#{real(error)}" }]
  end
end

if $PROGRAM_NAME == __FILE__
  recommender = Recommender.new(Ratings.read)
  recommender.train
  predictions = recommender.predict_tests
  recommender.prepare_rankings
  outputs = {
    'predictions.csv' => predictions,
    'evaluation.txt' => recommender.evaluation_report,
    'recommendations.txt' => recommender.recommendations,
    'similar_items.txt' => recommender.similar_items,
    'training_log.csv' => recommender.training_log
  }
  outputs.each { |filename, lines| Report.write_lines(File.join('output', filename), lines) }
end
