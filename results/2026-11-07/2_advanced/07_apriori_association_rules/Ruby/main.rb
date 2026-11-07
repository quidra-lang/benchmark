# frozen_string_literal: true

require 'set'
require_relative 'baskets'
require_relative 'apriori'
require_relative 'fpgrowth'
require_relative 'rules'
require_relative 'report'

class MarketAnalysis
  include Report

  def read_parameters
    @params = File.readlines('input/params.txt', chomp: true).to_h do |line|
      name, text = line.split(' ')
      value = text.include?('/') ? Rational(*text.split('/').map(&:to_i)) : text.to_i
      [name, value]
    end
  end

  def validate_input
    @errors = []
    @products = {}
    item_rows = Baskets.csv_records('input/items.csv')
    @item_rows = item_rows.length
    item_rows.each do |line, (name, category, price_text)|
      price = price_text.to_i
      error = if @products.key?(name)
                "duplicate item #{name}"
              elsif price.zero?
                "bad price #{price}"
              end
      if error
        @errors << "items.csv line #{line}: #{error}"
      else
        @products[name] = Baskets::Product.new(name, category, price)
      end
    end
    @transactions = []
    by_id = {}
    @adopted_lines = @rejected_lines = @duplicate_lines = 0
    transaction_rows = Baskets.csv_records('input/transactions.csv')
    @transaction_lines = transaction_rows.length
    transaction_rows.each do |line, (id, customer, day_text, item)|
      if !@transactions.empty? && @transactions.last.id != id && by_id.key?(id)
        @errors << "transactions.csv line #{line}: tid #{id} not contiguous"
        @rejected_lines += 1
        next
      end
      day = day_text.to_i
      unless by_id.key?(id)
        by_id[id] = Baskets::Transaction.new(id, customer, day)
        @transactions << by_id[id]
      end
      transaction = @transactions.last
      error = if customer != transaction.customer
                "tid #{id} customer #{customer} differs from #{transaction.customer}"
              elsif day != transaction.day
                "tid #{id} day #{day} differs from #{transaction.day}"
              elsif !@products.key?(item)
                "unknown item #{item}"
              end
      if error
        @errors << "transactions.csv line #{line}: #{error}"
        @rejected_lines += 1
      else
        @adopted_lines += 1
        @duplicate_lines += 1 if transaction.units.key?(item)
        transaction.units[item] += 1
      end
    end
    @baskets = @transactions.reject { |transaction| transaction.units.empty? }
    @names = @products.keys.sort
    @categories = @products.values.map(&:category).uniq.sort
    @category_map = @products.transform_values(&:category)
    @sets = @baskets.map(&:products)
    @extended = @baskets.map { |basket| basket.extended(@products) }
    @support = Apriori::SupportCounter.new(@sets)
    @extended_support = Apriori::SupportCounter.new(@extended)
    @customers = @baskets.group_by(&:customer)
    @first_day, @last_day = @baskets.map(&:day).minmax
    @size_counts = @sets.map(&:length).tally
    @largest = @size_counts.keys.max
    @count = @baskets.length
  end

  def run_apriori(counter, universe, minimum, category_exclusion: false)
    all = {}
    levels = []
    previous = []
    1.upto(@params['max_size']) do |size|
      if size == 1
        candidates = universe.sort.map { |item| [item] }
        statistics = { candidates: candidates.length, excluded: 0, pruned: 0, counted: candidates.length }
      else
        break if previous.empty?

        candidates, statistics = Apriori.candidates(previous, size, category_exclusion ? @category_map : nil)
      end
      counts = Apriori.count(candidates, counter)
      frequent = counts.select { |_itemset, count| count >= minimum }
      previous = frequent.keys.sort
      levels << statistics.merge(number: size, frequent: frequent.length, sets: previous)
      all.merge!(frequent)
    end
    { counts: all, levels: levels, counter: counter }
  end

  def size_order(itemsets)
    itemsets.sort_by { |items| [items.length, items] }
  end

  def each_proper_subset(items, include_empty: true)
    return enum_for(__method__, items, include_empty: include_empty) unless block_given?

    first = include_empty ? 0 : 1
    limit = (1 << items.length) - 1
    (first...limit).each do |mask|
      yield items.each_index.filter_map { |index| items[index] if mask[index] == 1 }
    end
  end

  def classify_itemsets
    closed = Set.new(@frequent.keys)
    maximal = Set.new(@frequent.keys)
    generators = []
    @frequent.each do |items, count|
      generator = true
      each_proper_subset(items) do |subset|
        support = subset.empty? ? @count : @frequent.fetch(subset)
        generator = false if support <= count
        next if subset.empty?

        maximal.delete(subset)
        closed.delete(subset) if support == count
      end
      generators << items if generator
    end
    @closed = size_order(closed.to_a)
    @maximal = size_order(maximal.to_a)
    @generators = size_order(generators)
  end

  def make_rules(run, total, category_only: false)
    counts = run[:counts]
    generated = 0
    kept = []
    counts.each do |combined, n_z|
      next if combined.length < 2
      next if category_only && combined.none? { |item| @categories.include?(item) }

      each_proper_subset(combined, include_empty: false) do |antecedent|
        consequent = combined - antecedent
        generated += 1
        rule = Rules.build(antecedent, consequent, counts.fetch(antecedent), counts.fetch(consequent), n_z, total)
        next unless Rules.passes?(rule, @params['min_confidence'], @params['min_lift'])

        previous_best = each_proper_subset(antecedent).map do |subset|
          denominator = subset.empty? ? total : counts.fetch(subset)
          Rational(counts.fetch((subset + consequent).sort), denominator)
        end.max
        rule.improvement = rule.confidence - previous_best
        kept << rule
      end
    end
    kept.sort! { |left, right| Rules.compare(left, right) }
    kept.each_with_index { |rule, index| rule.rank = index + 1 }
    { rules: kept, generated: generated, productive: kept.count { |rule| rule.improvement.positive? } }
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? Rational(sorted[middle], 1) : Rational(sorted[middle - 1] + sorted[middle], 2)
  end

  def minimum_gap(before, after)
    index = 0
    smallest = nil
    after.each do |day|
      index += 1 while index < before.length && before[index] < day
      next if index.zero?

      gap = day - before[index - 1]
      smallest = gap if smallest.nil? || gap < smallest
    end
    smallest
  end

  def analyze_sequences
    @days = {}
    @buyers = @names.to_h { |name| [name, 0] }
    @repeats = @names.to_h { |name| [name, { name: name, customers: 0, intervals: [] }] }
    gaps = Hash.new { |hash, pair| hash[pair] = [] }
    @customers.each do |customer, baskets|
      purchases = Hash.new { |hash, item| hash[item] = Set.new }
      baskets.each { |basket| basket.units.each_key { |item| purchases[item].add(basket.day) } }
      dates = purchases.transform_values { |days| days.to_a.sort }
      @days[customer] = dates
      dates.each do |item, days|
        @buyers[item] += 1
        next if days.length < 2

        @repeats[item][:customers] += 1
        days.each_cons(2) { |left, right| @repeats[item][:intervals] << right - left }
      end
      dates.each do |before, before_days|
        dates.each do |after, after_days|
          next unless before_days.first < after_days.last

          gaps[[before, after]] << minimum_gap(before_days, after_days)
        end
      end
    end
    @sequence_pairs = gaps.length
    @sequences = gaps.filter_map do |(before, after), values|
      next if values.length < @params['sequence_min_support']

      { before: before, after: after, count: values.length, confidence: Rational(values.length, @buyers[before]),
        lift: Rational(values.length * @customers.length, @buyers[before] * @buyers[after]), gap: median(values) }
    end
    @sequences.sort_by! { |sequence| [-sequence[:count], -sequence[:confidence], sequence[:before], sequence[:after]] }
    @repeats = @repeats.values.reject { |entry| entry[:intervals].empty? }
    @repeats.each do |entry|
      intervals = entry[:intervals]
      entry[:mean] = Rational(intervals.sum, intervals.length)
      entry[:median] = median(intervals)
    end
    @repeats.sort_by! { |entry| [entry[:mean], entry[:name]] }
  end

  def recommend(owned, candidates)
    selected = []
    candidates.each do |item|
      next if owned.include?(item) || selected.include?(item)

      selected << item
      break if selected.length == @params['recommend_top']
    end
    selected
  end

  def recommend_rules(owned, rules)
    candidates = rules.lazy.select { |rule| Baskets.contained?(rule.antecedent, owned) }.map { |rule| rule.consequent.first }
    recommend(owned, candidates)
  end

  def evaluate_periods
    train_sets = []
    test_sets = []
    @baskets.each_with_index do |basket, index|
      (basket.day <= @params['split_day'] ? train_sets : test_sets) << @sets[index]
    end
    @train_count = train_sets.length
    @test_count = test_sets.length
    train_counter = Apriori::SupportCounter.new(train_sets)
    test_counter = Apriori::SupportCounter.new(test_sets)
    @train_run = run_apriori(train_counter, @names, @params['train_min_support'])
    test_run = run_apriori(test_counter, @names, @params['test_min_support'])
    @training_rules = make_rules(@train_run, @train_count)[:rules]
    test_rules = make_rules(test_run, @test_count)[:rules]
    @verdict_counts = Hash.new(0)
    @verdicts = @training_rules.map do |rule|
      a = test_counter.count(rule.antecedent)
      b = test_counter.count(rule.consequent)
      count = test_counter.count(rule.antecedent + rule.consequent)
      confidence = lift = nil
      if a.zero? || b.zero?
        verdict = 'UNSEEN'
      else
        confidence = Rational(count, a)
        lift = Rational(@test_count * count, a * b)
        verdict = confidence >= @params['min_confidence'] && lift >= @params['min_lift'] ? 'HOLD' : 'FAIL'
      end
      @verdict_counts[verdict] += 1
      { rule: rule, count: count, base: a, confidence: confidence, lift: lift, verdict: verdict }
    end
    signatures = Set.new(@training_rules.map { |rule| [rule.antecedent, rule.consequent] })
    @emerging = test_rules.reject { |rule| signatures.include?([rule.antecedent, rule.consequent]) }
    popularity = @names.sort_by { |name| [-train_counter.count([name]), name] }
    single_rules = @training_rules.select { |rule| rule.consequent.length == 1 }
    @evaluation = Hash.new { |hash, size| hash[size] = { cases: 0, covered: 0, hit1: 0, hit: 0, baseline: 0 } }
    @heldout = Hash.new(0)
    @hits = Hash.new(0)
    recommendation_cache = {}
    test_sets.each do |basket|
      next if basket.length < 2

      basket.to_a.sort.each do |hidden|
        owned = basket.dup.delete(hidden)
        key = owned.to_a.sort
        recommendations, baseline = recommendation_cache[key] ||= [recommend_rules(owned, single_rules), recommend(owned, popularity)]
        statistics = @evaluation[basket.length]
        statistics[:cases] += 1
        statistics[:covered] += 1 unless recommendations.empty?
        statistics[:hit1] += 1 if recommendations.first == hidden
        statistics[:hit] += 1 if recommendations.include?(hidden)
        statistics[:baseline] += 1 if baseline.include?(hidden)
        @heldout[hidden] += 1
        @hits[hidden] += 1 if recommendations.include?(hidden)
      end
    end
    @evaluation_total = { cases: 0, covered: 0, hit1: 0, hit: 0, baseline: 0 }
    @evaluation.each_value { |values| values.each { |key, value| @evaluation_total[key] += value } }
  end

  def summarize_products
    @units = @names.to_h { |name| [name, 0] }
    @baskets.each { |basket| basket.units.each { |item, count| @units[item] += count } }
    @revenues = @names.to_h { |name| [name, @units[name] * @products[name].price] }
    @total_revenue = @revenues.values.sum
    @itemset_counts = Hash.new(0)
    partners = Hash.new { |hash, item| hash[item] = [] }
    adjacency = @names.to_h { |name| [name, Set.new] }
    @frequent.each do |items, count|
      items.each { |item| @itemset_counts[item] += 1 }
      next unless items.length == 2

      left, right = items
      lift = Rational(@count * count, @support.count([left]) * @support.count([right]))
      partners[left] << { name: right, count: count, lift: lift }
      partners[right] << { name: left, count: count, lift: lift }
      if lift >= @params['group_min_lift']
        adjacency[left].add(right)
        adjacency[right].add(left)
      end
    end
    @partners = partners.transform_values { |entries| entries.min_by { |entry| [-entry[:lift], -entry[:count], entry[:name]] } }
    @strongest = {}
    @main_rules[:rules].each do |rule|
      (rule.antecedent + rule.consequent).each { |item| @strongest[item] ||= rule }
    end
    @groups = []
    visited = Set.new
    @names.each do |name|
      next if visited.include?(name) || adjacency[name].empty?

      members = []
      stack = [name]
      visited.add(name)
      until stack.empty?
        item = stack.pop
        members << item
        adjacency[item].each do |neighbor|
          next if visited.include?(neighbor)

          visited.add(neighbor)
          stack << neighbor
        end
      end
      members.sort!
      core = members.min_by { |item| [-adjacency[item].length, -@support.count([item]), item] }
      @groups << { members: members, edges: members.sum { |item| adjacency[item].length } / 2,
                   core: core, revenue: members.sum { |item| @revenues[item] } }
    end
    @groups.sort_by! { |group| [-group[:members].length, group[:members].first] }
    @substitutes = []
    @main_run[:levels].first[:sets].map(&:first).combination(2) do |left, right|
      product = @support.count([left]) * @support.count([right])
      next if product < @params['negative_min_expected'] * @count

      count = @support.count([left, right])
      lift = Rational(@count * count, product)
      next if lift > @params['negative_max_lift']

      @substitutes << { left: left, right: right, count: count, expected: Rational(product, @count), lift: lift }
    end
    @substitutes.sort_by! { |pair| [pair[:lift], -pair[:expected], pair[:left], pair[:right]] }
    @category_totals = @categories.to_h do |category|
      members = @names.select { |name| @category_map[name] == category }
      [category, { products: members.length, units: members.sum { |name| @units[name] },
                   revenue: members.sum { |name| @revenues[name] } }]
    end
  end

  def summary_lines
    lines = @errors.map { |error| "ERROR #{error}" }
    lines << "ITEMS rows #{@item_rows} adopted #{@names.length} categories #{@categories.length}"
    lines << "TRANSACTIONS lines #{@transaction_lines} adopted #{@adopted_lines} rejected #{@rejected_lines} duplicates #{@duplicate_lines} transactions #{@transactions.length} empty #{@transactions.length - @count}"
    lines << "BASKETS count #{@count} customers #{@customers.length} first_day #{@first_day} last_day #{@last_day} average_size #{fraction(Rational(@sets.sum(&:length), @count))} largest #{@largest}"
    1.upto(@largest) do |size|
      count = @size_counts.fetch(size, 0)
      lines << "SIZE #{size} baskets #{count} share #{percentage(count, @count)}"
    end
    lines << "FREQUENT itemsets #{@frequent.length} closed #{@closed.length} maximal #{@maximal.length} generators #{@generators.length} levels #{@main_run[:levels].length}"
    match = @frequent == @fp_result
    statistics = @fp_statistics
    lines << "FPGROWTH header #{statistics[:header]} nodes #{statistics[:nodes]} conditional_trees #{statistics[:conditional_trees]} conditional_nodes #{statistics[:conditional_nodes]} itemsets #{statistics[:itemsets]} #{match ? 'MATCH' : 'MISMATCH'}"
    unless match
      [['ONLY_APRIORI', @frequent, @fp_result], ['ONLY_FPGROWTH', @fp_result, @frequent]].each do |label, left, right|
        size_order(left.keys.select { |items| !right.key?(items) || right[items] != left[items] }).each do |items|
          lines << "#{label} #{itemset(items)} #{left[items]}"
        end
      end
    end
    lines << "RULES generated #{@main_rules[:generated]} passed #{@main_rules[:rules].length} productive #{@main_rules[:productive]}"
    @category_run[:levels].each do |level|
      lines << "CATEGORY_LEVEL #{level[:number]} candidates #{level[:candidates]} taxonomy #{level[:excluded]} pruned #{level[:pruned]} counted #{level[:counted]} frequent #{level[:frequent]}"
    end
    lines << "CATEGORY_RULES itemsets #{@category_run[:counts].length} generated #{@category_rules[:generated]} passed #{@category_rules[:rules].length} productive #{@category_rules[:productive]}"
    multi_day = @customers.values.count { |baskets| baskets.map(&:day).uniq.length >= 2 }
    lines << "SEQUENCES customers #{@customers.length} multi_day #{multi_day} pairs #{@sequence_pairs} frequent #{@sequences.length}"
    lines
  end

  def itemset_lines
    @main_run[:levels].flat_map do |level|
      ["LEVEL #{level[:number]} candidates #{level[:candidates]} pruned #{level[:pruned]} counted #{level[:counted]} frequent #{level[:frequent]}"] +
        level[:sets].map { |items| "#{itemset(items)} #{@frequent[items]}" }
    end
  end

  def classification_lines
    [['CLOSED', @closed], ['MAXIMAL', @maximal], ['GENERATOR', @generators]].flat_map do |label, itemsets|
      itemsets.map { |items| "#{label} #{itemset(items)} #{@frequent[items]}" }
    end
  end

  def sequence_lines
    lines = @sequences.each_with_index.map do |sequence, index|
      "SEQ #{index + 1} #{sequence[:before]} -> #{sequence[:after]} customers #{sequence[:count]} base #{@buyers[sequence[:before]]} confidence #{fraction(sequence[:confidence])} lift #{fraction(sequence[:lift])} gap #{fraction(sequence[:gap])}"
    end
    @repeats.each do |entry|
      intervals = entry[:intervals]
      lines << "REPEAT #{entry[:name]} customers #{entry[:customers]} intervals #{intervals.length} min #{intervals.min} max #{intervals.max} mean #{fraction(entry[:mean])} median #{fraction(entry[:median])}"
    end
    lines
  end

  def rule_text(rule)
    "#{itemset(rule.antecedent)} -> #{itemset(rule.consequent)}"
  end

  def recommendation_line(label, counts)
    "RECOMMEND #{label} cases #{counts[:cases]} covered #{counts[:covered]} hit1 #{counts[:hit1]} hit #{counts[:hit]} rate #{fraction(Rational(counts[:hit], counts[:cases]))} baseline #{counts[:baseline]} rate #{fraction(Rational(counts[:baseline], counts[:cases]))}"
  end

  def validation_lines
    lines = @verdicts.map do |entry|
      rule = entry[:rule]
      confidence = entry[:confidence].nil? ? '-' : fraction(entry[:confidence])
      lift = entry[:lift].nil? ? '-' : fraction(entry[:lift])
      "RULE #{rule.rank} #{rule_text(rule)} train #{rule.count} confidence #{fraction(rule.confidence)} lift #{fraction(rule.lift)} test #{entry[:count]} of #{entry[:base]} confidence #{confidence} lift #{lift} #{entry[:verdict]}"
    end
    @emerging.each do |rule|
      lines << "EMERGING #{rule.rank} #{rule_text(rule)} test #{rule.count} confidence #{fraction(rule.confidence)} lift #{fraction(rule.lift)}"
    end
    lines << "VALIDATION train #{@train_count} test #{@test_count} itemsets #{@train_run[:counts].length} rules #{@training_rules.length} hold #{@verdict_counts['HOLD']} fail #{@verdict_counts['FAIL']} unseen #{@verdict_counts['UNSEEN']} emerging #{@emerging.length}"
    @evaluation.keys.sort.each { |size| lines << recommendation_line("size #{size}", @evaluation[size]) }
    lines << recommendation_line('total', @evaluation_total)
    lines
  end

  def append_matrix(lines, names, counter, label)
    counts = names.map { |name| counter.count([name]) }
    names.each_with_index { |name, index| lines << "#{label} #{index + 1} #{name} baskets #{counts[index]}" }
    lines << ' ' * 4 + (1..names.length).map { |index| index.to_s.rjust(7) }.join
    names.each_with_index do |name, row|
      cells = names.each_with_index.map do |other, column|
        value = row == column ? '-' : (100 * @count * counter.count([name, other]) / (counts[row] * counts[column])).to_s
        value.rjust(7)
      end
      lines << (row + 1).to_s.rjust(4) + cells.join
    end
  end

  def product_lines
    lines = @names.sort_by { |name| [-@revenues[name], name] }.each_with_index.map do |name, index|
      product = @products[name]
      count = @support.count([name])
      partner = @partners[name]
      partner_text = partner ? "#{partner[:name]} #{fraction(partner[:lift])}" : 'none'
      best = @strongest[name]
      best_text = best ? "#{best.rank} #{rule_text(best)}" : 'none'
      "ITEM #{index + 1} #{name} #{product.category} price #{money(product.price)} units #{@units[name]} revenue #{money(@revenues[name])} share #{percentage(@revenues[name], @total_revenue)} baskets #{count} support #{fraction(Rational(count, @count))} customers #{@buyers[name]} itemsets #{@itemset_counts[name]} heldout #{@heldout[name]} hits #{@hits[name]} partner #{partner_text} best #{best_text}"
    end
    @categories.sort_by { |name| [-@category_totals[name][:revenue], name] }.each do |name|
      values = @category_totals[name]
      count = @extended_support.count([name])
      lines << "CATEGORY #{name} items #{values[:products]} units #{values[:units]} revenue #{money(values[:revenue])} share #{percentage(values[:revenue], @total_revenue)} baskets #{count} support #{fraction(Rational(count, @count))}"
    end
    lines << "TOTAL items #{@names.length} units #{@units.values.sum} revenue #{money(@total_revenue)} baskets #{@count} customers #{@customers.length}"
    @groups.each_with_index do |group, index|
      lines << "GROUP #{index + 1} items #{group[:members].length} edges #{group[:edges]} core #{group[:core]} revenue #{money(group[:revenue])} share #{percentage(group[:revenue], @total_revenue)} members #{itemset(group[:members])}"
    end
    @substitutes.each do |pair|
      lines << "SUBSTITUTE #{pair[:left]} #{pair[:right]} count #{pair[:count]} expected #{fraction(pair[:expected])} lift #{fraction(pair[:lift])}"
    end
    products = @names.sort_by { |name| [-@support.count([name]), name] }.take(@params['matrix_size'])
    append_matrix(lines, products, @support, 'MATRIX')
    categories = @categories.sort_by { |name| [-@extended_support.count([name]), name] }
    append_matrix(lines, categories, @extended_support, 'CATEGORY_MATRIX')
    lines
  end

  def trend_lines
    weeks = (@last_day - 1) / 7 + 1
    series = (@categories + @names).to_h { |name| [name, Array.new(weeks, 0)] }
    baskets = Array.new(weeks, 0)
    units = Array.new(weeks, 0)
    customers = Array.new(weeks) { Set.new }
    @baskets.each do |basket|
      week = (basket.day - 1) / 7
      baskets[week] += 1
      customers[week].add(basket.customer)
      basket.units.each do |name, count|
        units[week] += count
        series[name][week] += count
        series[@category_map[name]][week] += count
      end
    end
    week_numbers = (1..weeks).to_a
    rows = [['WEEK', week_numbers], ['BASKETS', baskets], ['UNITS', units], ['CUSTOMERS', customers.map(&:length)]] + series.to_a
    lines = rows.map { |label, values| label.ljust(17) + values.map { |value| value.to_s.rjust(6) }.join }
    sum_w = week_numbers.sum
    denominator = weeks * week_numbers.sum { |week| week * week } - sum_w * sum_w
    trends = series.map do |name, values|
      total = values.sum
      weighted = values.each_with_index.sum { |value, index| (index + 1) * value }
      slope = Rational(weeks * weighted - sum_w * total, denominator)
      relative = total.zero? ? nil : slope * Rational(weeks, total)
      verdict = if relative.nil?
                  'NONE'
                elsif relative >= @params['trend_threshold']
                  'RISING'
                elsif relative <= -@params['trend_threshold']
                  'FALLING'
                else
                  'FLAT'
                end
      { name: name, total: total, slope: slope, relative: relative, verdict: verdict }
    end
    trends.sort_by! { |entry| [entry[:relative].nil? ? 1 : 0, entry[:relative].nil? ? 0 : -entry[:relative], entry[:name]] }
    trends.each do |entry|
      relative = entry[:relative].nil? ? '-' : fraction(entry[:relative])
      lines << "TREND #{entry[:name]} units #{entry[:total]} slope #{fraction(entry[:slope])} relative #{relative} #{entry[:verdict]}"
    end
    lines
  end

  def customer_lines
    segments = %w[NEW LOYAL AT_RISK REGULAR].to_h { |name| [name, { customers: 0, revenue: 0 }] }
    single_rules = @main_rules[:rules].select { |rule| rule.consequent.length == 1 }
    lines = @customers.keys.sort.map do |customer|
      baskets = @customers[customer]
      days = baskets.map(&:day).uniq.sort
      purchased = Set.new(@days[customer].keys)
      categories = Hash.new(0)
      units = revenue = 0
      baskets.each do |basket|
        basket.units.each do |name, count|
          units += count
          revenue += count * @products[name].price
          categories[@category_map[name]] += count
        end
      end
      favorite = categories.keys.min_by { |name| [-categories[name], name] }
      segment = if days.first > @last_day - 28
                  'NEW'
                elsif baskets.length >= 4 && @last_day - days.last <= 14
                  'LOYAL'
                elsif @last_day - days.last > 28
                  'AT_RISK'
                else
                  'REGULAR'
                end
      offer = recommend_rules(purchased, single_rules)
      segments[segment][:customers] += 1
      segments[segment][:revenue] += revenue
      "CUSTOMER #{customer} baskets #{baskets.length} days #{days.length} first #{days.first} last #{days.last} items #{purchased.length} units #{units} revenue #{money(revenue)} average #{money(revenue / baskets.length)} favorite #{favorite} segment #{segment} offer #{offer.empty? ? 'none' : itemset(offer)}"
    end
    segments.each do |name, values|
      lines << "SEGMENT #{name} customers #{values[:customers]} revenue #{money(values[:revenue])} share #{percentage(values[:revenue], @total_revenue)}"
    end
    lines
  end

  def run
    read_parameters
    validate_input
    @main_run = run_apriori(@support, @names, @params['min_support'])
    @frequent = @main_run[:counts]
    @fp_result, @fp_statistics = FPGrowth.mine(@sets, @params['min_support'], @params['max_size'])
    classify_itemsets
    @main_rules = make_rules(@main_run, @count)
    @category_run = run_apriori(@extended_support, @categories + @names, @params['category_min_support'], category_exclusion: true)
    @category_rules = make_rules(@category_run, @count, category_only: true)
    analyze_sequences
    evaluate_periods
    summarize_products
    write_files('summary.txt' => summary_lines, 'itemsets.txt' => itemset_lines,
                'closed_maximal.txt' => classification_lines,
                'rules.csv' => [Report::RULE_HEADER] + @main_rules[:rules].map { |rule| rule_csv(rule) },
                'category_rules.csv' => [Report::RULE_HEADER] + @category_rules[:rules].map { |rule| rule_csv(rule) },
                'sequences.txt' => sequence_lines, 'validation.txt' => validation_lines,
                'items_report.txt' => product_lines, 'trends.txt' => trend_lines, 'customers.txt' => customer_lines)
  end
end

MarketAnalysis.new.run
