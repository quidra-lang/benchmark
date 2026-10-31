# frozen_string_literal: true

require 'set'
require_relative 'transactions'
require_relative 'features'
require_relative 'kmeans'
require_relative 'validation'
require_relative 'profiles'
require_relative 'report'

class CustomerSegments
  CRITERIA = %i[elbow silhouette calinski_harabasz davies_bouldin hartigan].freeze

  def draw
    @random = (48_271 * @random) % 2_147_483_647
  end

  def seeds(points, count, method, run_number)
    chosen = []
    if method == 'forgy'
      while chosen.length < count
        index = draw % points.length
        chosen << index unless chosen.include?(index)
      end
      return chosen
    end
    if method == 'maximin'
      mean = KMeans.mean(points)
      ordered = points.each_index.sort_by { |index| [KMeans.squared_distance(points[index], mean), index] }
      chosen << ordered[run_number - 1]
    else
      chosen << draw % points.length
    end
    while chosen.length < count
      distances = points.map do |point|
        chosen.map { |index| KMeans.squared_distance(point, points[index]) }.min
      end
      if method == 'maximin'
        chosen << points.each_index.min_by { |index| [-distances[index], index] }
      else
        total = distances.reduce(0.0, :+)
        target = (draw / 2_147_483_647.0) * total
        cumulative = 0.0
        index = distances.each_index.find do |candidate|
          cumulative += distances[candidate]
          cumulative > target
        end
        chosen << (index || distances.rindex { |distance| distance.positive? })
      end
    end
    chosen
  end

  def refine(points, original, count)
    assignment = original.dup
    centers = KMeans.centers(points, assignment, count)
    sizes = KMeans.groups(assignment, count).map(&:length)
    passes = transfers = 0
    while passes < @limit
      moved = 0
      points.each_with_index do |point, index|
        source = assignment[index]
        next if sizes[source] == 1

        removal = sizes[source].fdiv(sizes[source] - 1) * KMeans.squared_distance(point, centers[source])
        costs = centers.each_index.reject { |group| group == source }.map do |group|
          [sizes[group].fdiv(sizes[group] + 1) * KMeans.squared_distance(point, centers[group]), group]
        end
        addition, target = costs.min
        next unless addition < removal

        assignment[index] = target
        sizes[source] -= 1
        sizes[target] += 1
        [source, target].each do |group|
          members = points.each_index.select { |member| assignment[member] == group }
          centers[group] = KMeans.mean(members.map { |member| points[member] })
        end
        moved += 1
      end
      passes += 1
      transfers += moved
      break if moved.zero?
    end
    centers = KMeans.centers(points, assignment, count)
    { assignment: assignment, centers: centers, passes: passes, transfers: transfers,
      sse: KMeans.sse(points, assignment, centers) }
  end

  def clustering_run(points, count, method, number)
    selected = seeds(points, count, method, number)
    lloyd = KMeans.lloyd(points, selected.map { |index| points[index] }, @limit)
    { method: method, number: number, seeds: selected, lloyd: lloyd,
      refined: refine(points, lloyd[:assignment], count) }
  end

  def organize(points, assignment, count)
    members = KMeans.groups(assignment, count).sort_by { |group| [-group.length, group.first] }
    relabeled = Array.new(points.length)
    members.each_with_index { |group, label| group.each { |index| relabeled[index] = label } }
    centers = members.map { |group| KMeans.mean(group.map { |index| points[index] }) }
    { members: members, assignment: relabeled, centers: centers, sse: KMeans.sse(points, relabeled, centers) }
  end

  def fit_solutions
    @solutions = {}
    @ks.each do |count|
      runs = []
      bests = {}
      @methods.each do |method|
        method_runs = (1..@params['RESTARTS']).map { |number| clustering_run(@points, count, method, number) }
        runs.concat(method_runs)
        bests[method] = method_runs.min_by { |run| [Report.key(run[:refined][:sse]), run[:number]] }
      end
      method = @methods.each_with_index.min_by { |name, index| [Report.key(bests[name][:refined][:sse]), index] }.first
      chosen = bests.fetch(method)
      solution = organize(@points, chosen[:refined][:assignment], count)
      solution[:runs] = runs
      solution[:bests] = bests
      solution[:chosen] = chosen
      solution[:indices] = Validation.indices(@points, solution[:assignment], solution[:centers], solution[:sse], @distances)
      used = Hash.new(0)
      solution[:names] = []
      solution[:rules] = []
      solution[:centers].each do |center|
        rule = Profiles.match_rule(center, @rules)
        used[rule] += 1
        name = @rules[rule][:name]
        solution[:names] << (used[rule] == 1 ? name : "#{name}_#{used[rule]}")
        solution[:rules] << rule + 1
      end
      @solutions[count] = solution
    end
    minimum, maximum = @ks.first, @ks.last
    @ks.each do |count|
      solution = @solutions[count]
      indices = solution[:indices]
      indices[:elbow] = Validation.elbow(count, minimum, maximum, solution[:sse], @solutions[minimum][:sse], @solutions[maximum][:sse])
      indices[:hartigan] = Validation.hartigan(solution[:sse], @solutions[count + 1][:sse], @customers.length, count) if count < maximum
    end
    @votes = {}
    CRITERIA.take(4).each do |criterion|
      candidates = criterion == :elbow ? @ks[1...-1] : @ks
      direction = criterion == :davies_bouldin ? 1 : -1
      @votes[criterion] = candidates.min_by { |count| [direction * Report.key(@solutions[count][:indices][criterion]), count] }
    end
    @votes[:hartigan] = @ks.find { |count| count < maximum && @solutions[count][:indices][:hartigan] <= 10 } || maximum
    @vote_counts = @votes.values.tally
    @chosen_k = @ks.min_by { |count| [-@vote_counts.fetch(count, 0), -Report.key(@solutions[count][:indices][:silhouette]), count] }
    @final = @solutions.fetch(@chosen_k)
  end

  def gini(spends)
    sorted = spends.sort
    total = sorted.sum
    weighted = sorted.each_with_index.sum { |spend, index| (index + 1) * spend }
    (2 * weighted - (sorted.length + 1) * total).fdiv(sorted.length * total)
  end

  def prepare_customers
    size = @customers.length
    @scores = @customers.map do |customer|
      recency = @customers.count { |other| other.raw[0] > customer.raw[0] }
      frequency = @customers.count { |other| other.raw[1] < customer.raw[1] }
      monetary = @customers.count { |other| other.spend < customer.spend }
      [recency, frequency, monetary].map { |count| 1 + 5 * count / size }
    end
    @codes = @scores.map(&:join)
    @details = @points.each_with_index.map do |point, index|
      own = @final[:assignment][index]
      distances = @final[:centers].map { |center| KMeans.squared_distance(point, center) }
      other = distances.each_index.reject { |group| group == own }.min_by { |group| [distances[group], group] }
      { distance: Math.sqrt(distances[own]), other: other, other_distance: Math.sqrt(distances[other]),
        silhouette: @final[:indices][:silhouettes][index] }
    end
    @total_spend = @customers.sum(&:spend)
    @category_spend = Hash.new(0)
    @customers.each { |customer| customer.category_spend.each { |name, amount| @category_spend[name] += amount } }
    @categories = @category_spend.keys.sort
    @orders_by_customer = @reference_orders.group_by(&:customer)
  end

  def segment_profile(members, group)
    customers = members.map { |index| @customers[index] }
    center = @final[:centers][group]
    spends = customers.map(&:spend)
    revenue = spends.sum
    categories = Hash.new(0)
    customers.each { |customer| customer.category_spend.each { |name, amount| categories[name] += amount } }
    ranking = categories.select { |_, amount| amount.positive? }.sort_by { |name, amount| [-amount, name] }.map(&:first)
    medians = Features::NAMES.each_index.map do |feature|
      values = customers.map { |customer| feature == 2 ? customer.spend : customer.raw[feature] }
      values.sort[(members.length - 1) / 2]
    end
    traits = center.each_index.sort_by { |feature| [-center[feature].abs, feature] }.take(2).map do |feature|
      "#{center[feature].positive? ? 'high' : 'low'}_#{Features::NAMES[feature]}"
    end
    cadence = customers.select { |customer| customer.raw[1] >= 2 }
    gaps = cadence.map { |customer| (customer.raw[5] - customer.raw[0]).fdiv(customer.raw[1] - 1) }
    overdue = cadence.count { |customer| customer.raw[0] * (customer.raw[1] - 1) > @params['OVERDUE_FACTOR'] * (customer.raw[5] - customer.raw[0]) }
    bins = Array.new(@params['ORDER_BINS'].length + 1, 0)
    customers.each do |customer|
      customer.orders.each { |order| bins[@params['ORDER_BINS'].count { |boundary| order.net >= boundary * 100 }] += 1 }
    end
    sse = members.reduce(0.0) { |sum, index| sum + KMeans.squared_distance(@points[index], center) }
    all_orders = customers.flat_map { |customer| @orders_by_customer.fetch(customer.id) }
    amounts = all_orders.flat_map { |order| order.rows.map(&:amount) }
    gross = amounts.select(&:positive?).sum
    returned = -amounts.select(&:negative?).sum
    silhouettes = members.map { |index| @details[index][:silhouette] }
    rfm = 3.times.map { |feature| members.reduce(0.0) { |sum, index| sum + @scores[index][feature] } / members.length }
    mode = members.map { |index| @codes[index] }.tally.sort_by { |code, count| [-count, code] }.first
    outliers = []
    if members.length >= 2
      mean, sd = Features.mean_sd(members.map { |index| @details[index][:distance] })
      threshold = mean + @params['OUTLIER_SD'] * sd
      outliers = members.select { |index| @details[index][:distance] > threshold }
    end
    { members: members, revenue: revenue, categories: categories, ranking: ranking, medians: medians, traits: traits,
      original: Profiles.original(center, @scaling[:mean], @scaling[:sd]),
      top: members.sort_by { |index| [-@customers[index].spend, index] }.take(@params['TOP_CUSTOMERS']),
      cadence: gaps.length, mean_gap: gaps.empty? ? nil : gaps.reduce(0.0, :+) / gaps.length, overdue: overdue,
      bins: bins, sse: sse, gini: gini(spends), return_rate: returned.fdiv(gross), returned: returned,
      cancelled: all_orders.count { |order| order.net <= 0 },
      silhouette: silhouettes.reduce(0.0, :+) / members.length, negative: silhouettes.count(&:negative?),
      rfm: rfm, mode: mode, outliers: outliers }
  end

  def prepare_profiles
    @profiles = @final[:members].each_with_index.map { |members, group| segment_profile(members, group) }
    @customers.each_with_index do |customer, index|
      ranking = @profiles[@final[:assignment][index]][:ranking]
      @details[index][:recommend] = ranking.find { |name| customer.category_spend[name] <= 0 } || '-'
    end
  end

  def yes_no(value)
    value ? 'yes' : 'no'
  end

  def reals(values)
    values.map { |value| Report.real(value) }.join(' ')
  end

  def block_lines(blocks)
    blocks.each_with_index.flat_map { |lines, index| index.zero? ? lines : [''] + lines }
  end

  def feature_lines
    lines = ['customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure']
    @customers.each do |customer|
      raw = customer.raw
      lines << ([customer.id, raw[0], raw[1], Report.amount(customer.spend), Report.real(raw[3]), raw[4], raw[5]] +
                customer.point.map { |value| Report.real(value) }).join(',')
    end
    lines
  end

  def run_lines
    blocks = @ks.map do |count|
      solution = @solutions[count]
      lines = ["k #{count}"]
      solution[:runs].each do |run|
        lloyd = run[:lloyd]
        refined = run[:refined]
        ids = run[:seeds].map { |index| @customers[index].id }.join(' ')
        lines << "run #{run[:method]} #{run[:number]} seeds #{ids} iterations #{lloyd[:iterations]} converged #{yes_no(lloyd[:converged])} reseeds #{lloyd[:reseeds]} sse #{Report.real(lloyd[:sse])} passes #{refined[:passes]} transfers #{refined[:transfers]} refined #{Report.real(refined[:sse])}"
      end
      @methods.each do |method|
        best = solution[:bests][method]
        lines << "best #{method} restart #{best[:number]} sse #{Report.real(best[:refined][:sse])}"
      end
      chosen = solution[:chosen]
      lines << "chosen #{chosen[:method]} restart #{chosen[:number]} sse #{Report.real(chosen[:refined][:sse])}"
      lines << "sizes #{solution[:members].map(&:length).join(' ')}"
      lines
    end
    block_lines(blocks)
  end

  def selection_lines
    indices = ['indices']
    names = ['segments']
    stability = ['stability']
    @ks.each do |count|
      solution = @solutions[count]
      measures = solution[:indices]
      hartigan = count == @ks.last ? '-' : Report.real(measures[:hartigan])
      indices << "k=#{count} sse #{Report.real(solution[:sse])} elbow #{Report.real(measures[:elbow])} silhouette #{Report.real(measures[:silhouette])} calinski_harabasz #{Report.real(measures[:calinski_harabasz])} davies_bouldin #{Report.real(measures[:davies_bouldin])} hartigan #{hartigan}"
      labels = solution[:members].each_with_index.map { |members, index| "#{solution[:names][index]}:#{members.length}" }
      names << "k=#{count} #{labels.join(' ')}"
      parts = ["k=#{count}"]
      @methods.each_with_index do |first, index|
        @methods.drop(index + 1).each do |last|
          ari = Validation.ari(solution[:bests][first][:refined][:assignment], solution[:bests][last][:refined][:assignment])
          parts.concat(["#{first}:#{last}", Report.real(ari)])
        end
      end
      parts << 'final'
      @methods.each do |method|
        parts.concat([method, Report.real(Validation.ari(solution[:bests][method][:refined][:assignment], solution[:assignment]))])
      end
      following = count == @ks.last ? '-' : Report.real(Validation.ari(solution[:assignment], @solutions[count + 1][:assignment]))
      parts.concat(['next', following])
      stability << parts.join(' ')
    end
    votes = ['votes'] + CRITERIA.map { |criterion| "#{criterion} k=#{@votes[criterion]}" }
    votes << "chosen k=#{@chosen_k} votes #{@vote_counts[@chosen_k]}"
    block_lines([indices, votes, names, stability])
  end

  def segment_lines
    lines = ['customer,segment,name,distance,other,other_distance,silhouette,recommend']
    @customers.each_with_index do |customer, index|
      group = @final[:assignment][index]
      detail = @details[index]
      lines << [customer.id, group + 1, @final[:names][group], Report.real(detail[:distance]), detail[:other] + 1,
                Report.real(detail[:other_distance]), Report.real(detail[:silhouette]), detail[:recommend]].join(',')
    end
    lines
  end

  def related(members, count)
    return "k=#{count} -" unless @ks.include?(count)

    assignment = @solutions[count][:assignment]
    overlaps = Array.new(count, 0)
    members.each { |index| overlaps[assignment[index]] += 1 }
    chosen = overlaps.each_index.min_by { |group| [-overlaps[group], group] }
    "k=#{count} segment #{chosen + 1} shared #{overlaps[chosen]}"
  end

  def profile_lines(profile, group)
    members = profile[:members]
    revenue = profile[:revenue]
    original = profile[:original].each_with_index.map { |value, index| "#{Features::NAMES[index]} #{Report.real(value)}" }
    median = profile[:medians]
    top = profile[:top].flat_map { |index| [@customers[index].id, Report.amount(@customers[index].spend)] }
    mean_gap = profile[:mean_gap].nil? ? '-' : Report.real(profile[:mean_gap])
    categories = profile[:ranking].take(@params['TOP_CATEGORIES']).flat_map do |name|
      share = profile[:categories][name].fdiv(revenue)
      lift = share / @category_spend[name].fdiv(@total_spend)
      [name, Report.real(share), Report.real(lift)]
    end
    outliers = profile[:outliers].map { |index| @customers[index].id }
    ["segment #{group + 1} #{@final[:names][group]} rule #{@final[:rules][group]} size #{members.length} share #{Report.real(members.length.fdiv(@customers.length))} revenue #{Report.amount(revenue)} revenue_share #{Report.real(revenue.fdiv(@total_spend))}",
     "  center #{reals(@final[:centers][group])}",
     "  value #{original.join(' ')}",
     "  traits #{profile[:traits].join(' ')}",
     "  median recency #{median[0]} frequency #{median[1]} monetary #{Report.amount(median[2])} basket #{Report.real(median[3])} categories #{median[4]} tenure #{median[5]}",
     "  related #{related(members, @chosen_k - 1)} #{related(members, @chosen_k + 1)}",
     "  top_customers #{top.join(' ')}",
     "  cadence customers #{profile[:cadence]} mean_gap #{mean_gap} overdue #{profile[:overdue]}",
     "  order_sizes #{profile[:bins].join(' ')}",
     "  sse #{Report.real(profile[:sse])} share #{Report.real(profile[:sse] / @final[:sse])}",
     "  gini #{Report.real(profile[:gini])}",
     "  returns rate #{Report.real(profile[:return_rate])} returned #{Report.amount(profile[:returned])} cancelled #{profile[:cancelled]}",
     "  silhouette #{Report.real(profile[:silhouette])} negative #{profile[:negative]}",
     "  rfm r #{Report.real(profile[:rfm][0])} f #{Report.real(profile[:rfm][1])} m #{Report.real(profile[:rfm][2])} mode #{profile[:mode].join(' ')}",
     "  categories #{categories.join(' ')}",
     '  ' + (['outliers', outliers.length] + outliers).join(' ')]
  end

  def profiles_lines
    blocks = [["segments k=#{@chosen_k} customers #{@customers.length} revenue #{Report.amount(@total_spend)} gini #{Report.real(gini(@customers.map(&:spend)))}"]]
    @profiles.each_with_index { |profile, group| blocks << profile_lines(profile, group) }
    numbers = (1..@chosen_k).to_a.join(' ')
    mix = ["category_mix #{numbers}"]
    @categories.each do |name|
      shares = @profiles.map { |profile| profile[:categories][name].fdiv(profile[:revenue]) }
      mix << "#{name} #{reals(shares)}"
    end
    rfm = ["rfm_recency #{numbers}"]
    5.downto(1) do |score|
      counts = @final[:members].map { |members| members.count { |index| @scores[index][0] == score } }
      rfm << "r=#{score} #{counts.join(' ')}"
    end
    rfm << "ari rfm_codes #{Report.real(Validation.ari(@codes, @final[:assignment]))}"
    centers = ['center_distances']
    @final[:centers].each_with_index do |center, group|
      distances = @final[:centers].map { |other| Math.sqrt(KMeans.squared_distance(center, other)) }
      centers << "#{group + 1} #{reals(distances)}"
    end
    block_lines(blocks + [mix, rfm, centers])
  end

  def subsample_lines
    count = @customers.length
    size = count * @params['SUBSAMPLE_PERCENT'] / 100
    jaccards = Array.new(@chosen_k) { [] }
    @params['SUBSAMPLES'].times do
      indices = (0...count).to_a
      size.times do |index|
        other = index + draw % (count - index)
        indices[index], indices[other] = indices[other], indices[index]
      end
      subset = indices.take(size).sort
      points = subset.map { |index| @points[index] }
      result = KMeans.lloyd(points, @final[:centers], @limit)
      groups = KMeans.groups(result[:assignment], @chosen_k)
      @chosen_k.times do |group|
        expected = subset.each_index.select { |index| @final[:assignment][subset[index]] == group }.to_set
        ratios = groups.map do |actual|
          intersection = actual.count { |index| expected.include?(index) }
          union = expected.length + actual.length - intersection
          union.zero? ? 0.0 : intersection.fdiv(union)
        end
        jaccards[group] << ratios.max
      end
    end
    lines = ["subsamples #{@params['SUBSAMPLES']} size #{size}"]
    jaccards.each_with_index do |values, group|
      lines << "segment #{group + 1} #{@final[:names][group]} mean_jaccard #{Report.real(values.reduce(0.0, :+) / values.length)} min_jaccard #{Report.real(values.min)}"
    end
    lines
  end

  def robustness_lines
    subsamples = subsample_lines
    ablation = ['ablation']
    Features::NAMES.each_with_index do |name, feature|
      points = @points.map { |point| point.each_index.reject { |index| index == feature }.map { |index| point[index] } }
      run = clustering_run(points, @chosen_k, 'maximin', 1)
      ids = run[:seeds].map { |index| @customers[index].id }.join(' ')
      lloyd = run[:lloyd]
      refined = run[:refined]
      ari = Validation.ari(refined[:assignment], @final[:assignment])
      ablation << "without #{name} seeds #{ids} iterations #{lloyd[:iterations]} converged #{yes_no(lloyd[:converged])} transfers #{refined[:transfers]} sse #{Report.real(refined[:sse])} ari #{Report.real(ari)}"
    end
    members = @final[:members][0]
    points = members.map { |index| @points[index] }
    run = clustering_run(points, 2, 'maximin', 1)
    parts = organize(points, run[:refined][:assignment], 2)
    ids = run[:seeds].map { |index| @customers[members[index]].id }.join(' ')
    before = @profiles[0][:sse]
    after = run[:refined][:sse]
    lloyd = run[:lloyd]
    drilldown = ["drilldown segment 1 #{@final[:names][0]} size #{members.length} seeds #{ids} iterations #{lloyd[:iterations]} converged #{yes_no(lloyd[:converged])} transfers #{run[:refined][:transfers]}",
                 "sse before #{Report.real(before)} after #{Report.real(after)} gain #{Report.real(before - after)}"]
    parts[:members].each_with_index do |group, index|
      drilldown << "part #{index + 1} size #{group.length} center #{reals(parts[:centers][index])}"
    end
    block_lines([subsamples, ablation, drilldown])
  end

  def period_lines
    days = @params['PERIOD_DAYS']
    periods = @params['PERIODS']
    lines = ["periods #{periods} days #{days}"]
    1.upto(periods) do |period|
      first = @reference_day - period * days + 1
      last = @reference_day - (period - 1) * days
      revenue = []
      active = []
      acquired = []
      @profiles.each do |profile|
        customers = profile[:members].map { |index| @customers[index] }
        purchases = customers.map { |customer| customer.orders.select { |order| order.day.between?(first, last) } }
        revenue << Report.amount(purchases.flatten.sum(&:net))
        active << purchases.count { |orders| !orders.empty? }
        acquired << customers.count { |customer| (@reference_day - customer.raw[5]).between?(first, last) }
      end
      lines << "period #{period} days #{first} #{last} revenue #{revenue.join(' ')} active #{active.join(' ')} acquired #{acquired.join(' ')}"
    end
    lines
  end

  def migration_lines
    day = @params['SNAPSHOT_DAY']
    snapshot = Features.customers(day, @snapshot_orders)
    assignments = snapshot.to_h do |customer|
      point = Features.standardize(customer.transformed, @scaling[:mean], @scaling[:sd])
      group = @final[:centers].each_index.min_by { |index| [KMeans.squared_distance(point, @final[:centers][index]), index] }
      [customer.id, group]
    end
    table = Array.new(@chosen_k + 1) { Array.new(@chosen_k, 0) }
    moved_lines = ['moved_customers']
    stayed = moved = fresh = 0
    @customers.each_with_index do |customer, index|
      current = @final[:assignment][index]
      previous = assignments.fetch(customer.id, @chosen_k)
      table[previous][current] += 1
      if previous == @chosen_k
        fresh += 1
      elsif previous == current
        stayed += 1
      else
        moved += 1
        moved_lines << "#{customer.id} #{previous + 1} #{current + 1}"
      end
    end
    lost = snapshot.count { |customer| !@customer_ids.include?(customer.id) }
    lines = ["migration day #{day} customers #{snapshot.length}", 'from\\to ' + (1..@chosen_k).to_a.join(' ')]
    table.each_with_index { |row, index| lines << "#{index == @chosen_k ? 'none' : index + 1} #{row.join(' ')}" }
    lines + moved_lines + ["stayed #{stayed} moved #{moved} new #{fresh} lost #{lost}"]
  end

  def outcome_lines
    purchases = @outcome_orders.select { |order| order.net.positive? }.group_by(&:customer)
    lines = ["outcome days #{@reference_day + 1} #{@reference_day + @params['OUTCOME_DAYS']}"]
    @profiles.each_with_index do |profile, group|
      ids = profile[:members].map { |index| @customers[index].id }
      buyers = ids.count { |id| purchases.key?(id) }
      spend = ids.sum { |id| purchases.fetch(id, []).sum(&:net) }
      size = ids.length
      lines << "segment #{group + 1} #{@final[:names][group]} size #{size} buyers #{buyers} rate #{Report.real(buyers.fdiv(size))} revenue #{Report.amount(spend)} per_customer #{Report.real((spend / 100.0) / size)}"
    end
    unsegmented = purchases.keys.reject { |id| @customer_ids.include?(id) }
    revenue = unsegmented.sum { |id| purchases[id].sum(&:net) }
    lines + ["unsegmented buyers #{unsegmented.length} revenue #{Report.amount(revenue)}"]
  end

  def summary_lines
    used = @data[:rows].select { |row| row.day <= @reference_day }
    valid = @reference_orders.count { |order| order.net.positive? }
    excluded = @data[:customers].reject { |id| @customer_ids.include?(id) }.sort
    data = ["rows #{@data[:total]} duplicates #{@data[:duplicates]} zero #{@data[:free]} used #{used.length} returns #{used.count { |row| row.amount.negative? }} later #{@data[:rows].length - used.length}",
            "orders #{@reference_orders.length} valid #{valid} cancelled #{@reference_orders.length - valid}",
            "customers #{@data[:customers].length} clustered #{@customers.length} excluded #{excluded.length}",
            "excluded_ids #{excluded.empty? ? '-' : excluded.join(' ')}"]
    categories = @categories.map do |name|
      customers = @customers.count { |customer| customer.category_spend[name].positive? }
      "category #{name} revenue #{Report.amount(@category_spend[name])} share #{Report.real(@category_spend[name].fdiv(@total_spend))} customers #{customers}"
    end
    features = Features::NAMES.each_with_index.map do |name, feature|
      transform = Features::SQUARE_ROOT.include?(feature) ? 'sqrt' : 'none'
      "feature #{name} transform #{transform} raw_mean #{Report.real(@scaling[:raw_mean][feature])} raw_sd #{Report.real(@scaling[:raw_sd][feature])} mean #{Report.real(@scaling[:mean][feature])} sd #{Report.real(@scaling[:sd][feature])}"
    end
    correlation = ['correlation ' + Features::NAMES.join(' ')]
    Features.correlation(@points).each_with_index { |values, index| correlation << "#{Features::NAMES[index]} #{reals(values)}" }
    block_lines([data, categories, features, correlation])
  end

  def run
    @params = Transactions.settings('input/params.txt')
    @data = Transactions.read('input/transactions.csv')
    @rules = Profiles.rules('input/segment_rules.txt')
    @reference_day = @params['REFERENCE_DAY']
    @reference_orders = Transactions.orders(@data[:rows], 1, @reference_day)
    @snapshot_orders = Transactions.orders(@data[:rows], 1, @params['SNAPSHOT_DAY'])
    @outcome_orders = Transactions.orders(@data[:rows], @reference_day + 1, @reference_day + @params['OUTCOME_DAYS'])
    @customers = Features.customers(@reference_day, @reference_orders)
    @customer_ids = @customers.map(&:id).to_set
    @scaling = Features.scale(@customers)
    @points = @customers.map(&:point)
    @distances = Validation.distance_table(@points)
    @ks = (@params['K_RANGE'][0]..@params['K_RANGE'][1]).to_a
    @methods = @params['METHODS']
    @limit = @params['MAX_ITERATIONS']
    @random = @params['SEED']
    fit_solutions
    prepare_customers
    prepare_profiles
    Dir.mkdir('output') unless Dir.exist?('output')
    Report.write('features.csv', feature_lines)
    Report.write('runs.txt', run_lines)
    Report.write('selection.txt', selection_lines)
    Report.write('segments.csv', segment_lines)
    Report.write('profiles.txt', profiles_lines)
    Report.write('robustness.txt', robustness_lines)
    Report.write('tracking.txt', block_lines([period_lines, migration_lines, outcome_lines]))
    Report.write('summary.txt', summary_lines)
  end
end

CustomerSegments.new.run
