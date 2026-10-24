# frozen_string_literal: true

require_relative 'dataset'
require_relative 'impurity'
require_relative 'tree_builder'
require_relative 'pruning'
require_relative 'evaluation'

class DecisionTreeStudy
  View = Struct.new(:root, :cuts)
  Condition = Struct.new(:attribute, :lower, :upper, :equality, :excluded, keyword_init: true)
  Rule = Struct.new(:number, :leaf, :conditions, :generalized, :removed,
                    :validation, :test, keyword_init: true)

  class Minstd
    def initialize(seed)
      @state = seed
    end

    def draw
      @state = (48_271 * @state) % 2_147_483_647
    end
  end

  def initialize
    @data = Dataset.read
    @attributes, @classes = @data.attributes, @data.classes
    @train, @validation, @test = @data.train, @data.validation, @data.test
    @settings = @data.settings
    @n, @v, @m = @train.length, @validation.length, @test.length
    @builder = TreeBuilder.new(@attributes, @classes.length, @settings)
  end

  def structure(tree)
    nodes = Evaluation.nodes(tree.root, tree.cuts)
    leaves = nodes.select { |node| Evaluation.leaf?(node, tree.cuts) }
    { all: nodes, nodes: nodes.length, leaves: leaves.length,
      depth: leaves.map(&:depth).max, errors: leaves.sum { |node| node.stats.errors } }
  end

  def correct(tree, rows)
    Evaluation.correct(tree.root, rows, tree.cuts)
  end

  def predictions(tree, rows)
    rows.map { |row| Evaluation.predict(tree.root, row, tree.cuts) }
  end

  def correct_predictions(values, rows = @test)
    rows.each_index.count { |index| values[index] == rows[index].klass }
  end

  def build_primary_trees
    @grown = View.new(@builder.grow(@train), {})
    cuts, @pruning_decisions = Pruning.reduced_error(@grown.root, @validation)
    @pruned = View.new(@grown.root, cuts)
    @routes = {}
    { grown: @grown, pruned: @pruned }.each do |name, tree|
      @routes[name] = @test.map { |row| Evaluation.route(tree.root, row, tree.cuts) }
    end
    @models = @routes.transform_values { |routes| routes.map { |route| route.leaf.stats.majority } }
  end

  def depth_view(root, depth)
    cuts = {}
    Evaluation.nodes(root).each do |node|
      cuts[node.number] = true if node.split && node.depth == depth
    end
    View.new(root, cuts)
  end

  def cross_validation
    count = @settings[:folds]
    @folds = count.times.map do |fold|
      first = (fold * @n).div(count)
      finish = ((fold + 1) * @n).div(count)
      held = @train[first...finish]
      training = @train.first(first) + @train.drop(finish)
      tree = View.new(@builder.grow(training), {})
      { first: first + 1, last: finish, held: held, tree: tree,
        correct: correct(tree, held), leaves: structure(tree)[:leaves] }
    end
    @depths = (0..@settings[:max_depth]).map do |depth|
      tree = depth_view(@grown.root, depth)
      fold_correct = @folds.sum do |fold|
        correct(depth_view(fold[:tree].root, depth), fold[:held])
      end
      { depth: depth, tree: tree, leaves: structure(tree)[:leaves], cv: fold_correct,
        train: correct(tree, @train), validation: correct(tree, @validation), test: correct(tree, @test) }
    end
    @selected_depth = @depths.min_by { |entry| [-entry[:cv], entry[:depth]] }
    @models[:depth] = predictions(@selected_depth[:tree], @test)
  end

  def cost_complexity_selection
    @sequence = Pruning.cost_complexity(@grown.root).each_with_index.map do |entry, index|
      tree = View.new(@grown.root, entry.cuts)
      { index: index, entry: entry, tree: tree, validation_errors: @v - correct(tree, @validation) }
    end
    @selected_sequence = @sequence.min_by { |entry| [entry[:validation_errors], -entry[:index]] }
    @models[:cost_complexity] = predictions(@selected_sequence[:tree], @test)
  end

  def vote_prediction(votes)
    votes.index(votes.max)
  end

  def bagging
    generator = Minstd.new(@settings[:bag_seed])
    out_of_bag_votes = Array.new(@n) { Array.new(@classes.length, 0) }
    @test_votes = Array.new(@m) { Array.new(@classes.length, 0) }
    @bags = []
    @settings[:bag_trees].times do
      seen = {}
      sample = Array.new(@n) do
        index = generator.draw % @n
        seen[index] = true
        @train[index]
      end
      tree = View.new(@builder.grow(sample), {})
      out_of_bag = @train.reject { |row| seen[row.index] }
      out_of_bag_correct = 0
      out_of_bag.each do |row|
        prediction = Evaluation.predict(tree.root, row)
        out_of_bag_votes[row.index][prediction] += 1
        out_of_bag_correct += 1 if prediction == row.klass
      end
      @test.each_with_index do |row, index|
        prediction = Evaluation.predict(tree.root, row)
        @test_votes[index][prediction] += 1
      end
      @bags << { distinct: seen.length, leaves: structure(tree)[:leaves],
                 correct: out_of_bag_correct, size: out_of_bag.length }
    end
    @oob_correct = 0
    @oob_voted = 0
    out_of_bag_votes.each_with_index do |votes, index|
      next if votes.all?(&:zero?)

      @oob_voted += 1
      @oob_correct += 1 if vote_prediction(votes) == @train[index].klass
    end
    @models[:bagging] = @test_votes.map { |votes| vote_prediction(votes) }
  end

  def simplify(path)
    @attributes.filter_map do |attribute|
      parts = path.select { |split, _left| split.attribute.index == attribute.index }
      next if parts.empty?

      if attribute.type == 'INT'
        lower = parts.reject { |_split, left| left }.map { |split, _left| split.value }.max
        upper = parts.select { |_split, left| left }.map { |split, _left| split.value }.min
        Condition.new(attribute: attribute, lower: lower, upper: upper)
      else
        equality = parts.find { |_split, left| left }
        excluded = parts.reject { |_split, left| left }.map { |split, _left| split.value }.uniq.sort
        Condition.new(attribute: attribute, equality: equality&.first&.value, excluded: excluded)
      end
    end
  end

  def satisfies?(row, condition)
    value = row.values[condition.attribute.index]
    return false if value.nil?

    if condition.attribute.type == 'INT'
      (condition.lower.nil? || 2 * value > condition.lower) &&
        (condition.upper.nil? || 2 * value <= condition.upper)
    elsif !condition.equality.nil?
      value == condition.equality
    else
      !condition.excluded.include?(value)
    end
  end

  def coverage(conditions, klass, rows)
    hit = 0
    covered = 0
    rows.each do |row|
      next unless conditions.all? { |condition| satisfies?(row, condition) }

      covered += 1
      hit += 1 if row.klass == klass
    end
    [hit, covered]
  end

  def generalize(conditions, klass)
    current = conditions.dup
    removed = []
    until current.empty?
      hit, covered = coverage(current, klass, @validation)
      estimate = Rational(hit + 1, covered + @classes.length)
      best = nil
      current.each_index do |index|
        trial = current.each_with_index.filter_map { |condition, position| condition unless position == index }
        trial_hit, trial_covered = coverage(trial, klass, @validation)
        trial_estimate = Rational(trial_hit + 1, trial_covered + @classes.length)
        if best.nil? || trial_estimate > best[:estimate]
          best = { conditions: trial, removed: current[index].attribute.name, estimate: trial_estimate }
        end
      end
      break if best[:estimate] < estimate

      current = best[:conditions]
      removed << best[:removed]
    end
    [current, removed]
  end

  def build_rules
    @rules = []
    visit = lambda do |node, path|
      if Evaluation.leaf?(node, @pruned.cuts)
        conditions = simplify(path)
        generalized, removed = generalize(conditions, node.stats.majority)
        @rules << Rule.new(number: @rules.length + 1, leaf: node, conditions: conditions,
                           generalized: generalized, removed: removed,
                           validation: coverage(generalized, node.stats.majority, @validation),
                           test: coverage(generalized, node.stats.majority, @test))
      else
        visit.call(node.left, path + [[node.split, true]])
        visit.call(node.right, path + [[node.split, false]])
      end
    end
    visit.call(@pruned.root, [])
    @rule_by_leaf = @rules.to_h { |rule| [rule.leaf.number, rule] }
  end

  def condition_text(condition)
    name = condition.attribute.name
    if condition.attribute.type == 'INT'
      if !condition.lower.nil? && !condition.upper.nil?
        "#{TreeBuilder.threshold(condition.lower)} < #{name} <= #{TreeBuilder.threshold(condition.upper)}"
      elsif !condition.lower.nil?
        "#{name} > #{TreeBuilder.threshold(condition.lower)}"
      else
        "#{name} <= #{TreeBuilder.threshold(condition.upper)}"
      end
    elsif !condition.equality.nil?
      "#{name} = #{condition.attribute.values[condition.equality]}"
    else
      values = condition.excluded.map { |index| condition.attribute.values[index] }
      values.length == 1 ? "#{name} != #{values.first}" : "#{name} not in {#{values.join(',')}}"
    end
  end

  def conditions_text(conditions)
    conditions.empty? ? 'true' : conditions.map { |condition| condition_text(condition) }.join(' and ')
  end

  def learning_curve
    @curve = @settings[:curve].map do |size|
      grown = View.new(@builder.grow(@train.first(size)), {})
      cuts, = Pruning.reduced_error(grown.root, @validation)
      pruned = View.new(grown.root, cuts)
      { size: size, grown_leaves: structure(grown)[:leaves], grown_correct: correct(grown, @test),
        pruned_leaves: structure(pruned)[:leaves], pruned_correct: correct(pruned, @test) }
    end
  end

  def impurity_importance(tree)
    importance = Array.new(@attributes.length, 0.0)
    splits = Array.new(@attributes.length, 0)
    Evaluation.nodes(tree.root, tree.cuts).each do |node|
      next if Evaluation.leaf?(node, tree.cuts)

      attribute = node.split.attribute.index
      importance[attribute] += Impurity.decrease(node.stats, node.left.stats, node.right.stats)
      splits[attribute] += 1
    end
    total = 0.0
    importance.each { |value| total += value }
    entries = @attributes.map do |attribute|
      index = attribute.index
      share = total.zero? ? 0.0 : importance[index] / total
      rounded_share = Evaluation.real(share)
      { attribute: attribute, decrease: importance[index] / @n, share: rounded_share,
        rank_value: rounded_share.delete('.').to_i, splits: splits[index] }
    end
    entries.sort_by { |entry| [-entry[:rank_value], entry[:attribute].index] }
  end

  def permutation_importance
    generator = Minstd.new(@settings[:permutation_seed])
    base = correct_predictions(@models[:pruned])
    repeats = @settings[:permutation_repeats]
    @permutations = @attributes.map do |attribute|
      counts = Array.new(repeats) do
        values = @test.map { |row| row.values[attribute.index] }
        (@m - 1).downto(1) do |index|
          other = generator.draw % (index + 1)
          values[index], values[other] = values[other], values[index]
        end
        trial = @test.each_with_index.map do |row, index|
          attributes = row.values.dup
          attributes[attribute.index] = values[index]
          Dataset::Row.new(id: row.id, values: attributes, klass: row.klass, index: row.index)
        end
        correct(@pruned, trial)
      end
      { attribute: attribute, counts: counts, drop: repeats * base - counts.sum }
    end
    @permutations.sort_by! { |entry| [-entry[:drop], entry[:attribute].index] }
  end

  def root_candidate_lines
    candidates = @attributes.filter_map { |attribute| @builder.best_for_attribute(@train, attribute) }
    candidates.sort! do |first, second|
      comparison = second.quality <=> first.quality
      comparison.zero? ? first.split.attribute.index <=> second.split.attribute.index : comparison
    end
    stats = @grown.root.stats
    lines = ["root candidates n #{@n} counts #{stats.counts.join(' ')}"]
    candidates.each_with_index do |candidate, index|
      gain = candidate.quality.to_f / @n - stats.squares.to_f / (@n * @n)
      lines << "#{index + 1} #{candidate.split.condition} left #{candidate.left_stats.size} right #{candidate.right_stats.size} gain #{Evaluation.real(gain, 6)}"
    end
    lines
  end

  def tree_lines(tree)
    info = structure(tree)
    by_number = info[:all].to_h { |node| [node.number, node] }
    lines = info[:all].map do |node|
      condition = node.number == 1 ? 'root' : by_number[node.number.div(2)].split.condition(node.number.even?)
      text = "#{'  ' * node.depth}#{node.number} #{condition} n #{node.stats.size} counts #{node.stats.counts.join(' ')}"
      text += " leaf #{@classes[node.stats.majority]}" if Evaluation.leaf?(node, tree.cuts)
      text
    end
    lines << ''
    lines << "nodes #{info[:nodes]} leaves #{info[:leaves]} depth #{info[:depth]} errors #{Evaluation.ratio(info[:errors], @n)}"
    0.upto(info[:depth]) do |depth|
      nodes = info[:all].select { |node| node.depth == depth }
      leaves = nodes.select { |node| Evaluation.leaf?(node, tree.cuts) }
      lines << "level #{depth} nodes #{nodes.length} leaves #{leaves.length} rows #{leaves.sum { |node| node.stats.size }} errors #{leaves.sum { |node| node.stats.errors }}"
    end
    lines
  end

  def surrogate_lines
    lines = ['surrogates']
    Evaluation.nodes(@grown.root).each do |node|
      next if node.split.nil?

      list = node.surrogates.map do |surrogate|
        "#{surrogate.split.condition} #{surrogate.direction} #{surrogate.score}/#{node.stats.size}"
      end
      list = list.empty? ? 'none' : list.join(' ; ')
      lines << "node #{node.number} split #{node.split.condition} default #{node.default_left ? 'left' : 'right'} surrogates #{list}"
    end
    lines
  end

  def pruning_lines
    lines = ["reduced_error_pruning validation #{@v}"]
    @pruning_decisions.each do |decision|
      node = decision.node
      lines << "node #{node.number} depth #{node.depth} rows #{decision.rows} leaf #{decision.leaf_error} subtree #{decision.subtree_error} #{decision.pruned ? 'pruned' : 'kept'}"
    end
    pruned = @pruning_decisions.count(&:pruned)
    lines << "examined #{@pruning_decisions.length} pruned #{pruned} kept #{@pruning_decisions.length - pruned}"
    lines
  end

  def prediction_lines
    lines = ['id,predicted,actual,grown,leaf,path,missing']
    @test.each_with_index do |row, index|
      route = @routes[:pruned][index]
      path = route.path.map(&:number).join('-')
      missing = route.steps.count { |step| step.method != :primary }
      lines << [row.id, @classes[@models[:pruned][index]], @classes[row.klass],
                @classes[@models[:grown][index]], route.leaf.number, path, missing].join(',')
    end
    lines
  end

  def rule_lines
    lines = ["rules #{@rules.length}"]
    @rules.each do |rule|
      klass = rule.leaf.stats.majority
      indices = @test.each_index.select { |index| @routes[:pruned][index].leaf.number == rule.leaf.number }
      hit = indices.count { |index| @test[index].klass == klass }
      train = Evaluation.ratio(rule.leaf.stats.counts[klass], rule.leaf.stats.size)
      lines << "rule #{rule.number} node #{rule.leaf.number} if #{conditions_text(rule.conditions)} then #{@classes[klass]} train #{train} test #{Evaluation.ratio(hit, indices.length)}"
    end
    lines
  end

  def generalized_lines
    lines = ["generalized #{@rules.length}"]
    @rules.each do |rule|
      removed = rule.removed.empty? ? 'none' : rule.removed.join(',')
      hit, covered = rule.validation
      estimate = Evaluation.fraction(hit + 1, covered + @classes.length)
      lines << "general #{rule.number} if #{conditions_text(rule.generalized)} then #{@classes[rule.leaf.stats.majority]} removed #{removed} laplace #{estimate} validation #{hit}/#{covered} test #{rule.test.join('/')}"
    end
    lines
  end

  def misclassification_lines
    indices = @test.each_index.select { |index| @models[:pruned][index] != @test[index].klass }
    lines = ["misclassified #{indices.length}"]
    indices.each do |index|
      row = @test[index]
      route = @routes[:pruned][index]
      explanation = route.steps.map do |step|
        condition = step.node.split.condition(step.left)
        step.method == :primary ? condition : "#{condition} [#{step.method}]"
      end
      path = explanation.empty? ? 'root' : explanation.join('; ')
      lines << "#{row.id} actual #{@classes[row.klass]} predicted #{@classes[route.leaf.stats.majority]} rule #{@rule_by_leaf[route.leaf.number].number} path #{path}"
    end
    lines
  end

  def data_lines
    lines = ["data train #{@n} validation #{@v} test #{@m} attributes #{@attributes.length} classes #{@classes.length} target #{@data.target}"]
    counts = [@train, @validation, @test].map { |rows| Impurity.statistics(rows, @classes.length).counts }
    @classes.each_with_index do |name, index|
      lines << "class #{name} train #{counts[0][index]} validation #{counts[1][index]} test #{counts[2][index]}"
    end
    missing = [@validation, @test].map do |rows|
      @attributes.map { |attribute| rows.count { |row| row.values[attribute.index].nil? } }
    end
    lines << "missing validation #{missing[0].sum} test #{missing[1].sum}"
    @attributes.each do |attribute|
      lines << "missing #{attribute.name} validation #{missing[0][attribute.index]} test #{missing[1][attribute.index]}"
    end
    lines
  end

  def tree_summary_lines
    { grown: @grown, pruned: @pruned }.map do |name, tree|
      info = structure(tree)
      "#{name} nodes #{info[:nodes]} leaves #{info[:leaves]} depth #{info[:depth]} train #{Evaluation.ratio(correct(tree, @train), @n)} validation #{Evaluation.ratio(correct(tree, @validation), @v)} test #{Evaluation.ratio(correct_predictions(@models[name]), @m)}"
    end
  end

  def routing_lines
    internals = Evaluation.nodes(@pruned.root, @pruned.cuts).reject { |node| Evaluation.leaf?(node, @pruned.cuts) }
    counts = internals.to_h { |node| [node.number, { primary: 0, surrogate: 0, default: 0 }] }
    @routes[:pruned].each do |route|
      route.steps.each { |step| counts[step.node.number][step.method] += 1 }
    end
    lines = ['routing pruned test']
    internals.each do |node|
      tally = counts[node.number]
      lines << "node #{node.number} rows #{tally.values.sum} primary #{tally[:primary]} surrogate #{tally[:surrogate]} default #{tally[:default]}"
    end
    [false, true].each do |incomplete|
      indices = @test.each_index.select { |index| @test[index].values.any?(&:nil?) == incomplete }
      hit = indices.count { |index| @models[:pruned][index] == @test[index].klass }
      lines << "#{incomplete ? 'incomplete' : 'complete'} rows #{indices.length} correct #{Evaluation.ratio(hit, indices.length)}"
    end
    lines
  end

  def cross_validation_lines
    lines = ["cross_validation folds #{@settings[:folds]}"]
    @folds.each_with_index do |fold, index|
      lines << "fold #{index + 1} rows #{fold[:first]}-#{fold[:last]} leaves #{fold[:leaves]} correct #{Evaluation.ratio(fold[:correct], fold[:held].length)}"
    end
    lines << "cv accuracy #{Evaluation.ratio(@folds.sum { |fold| fold[:correct] }, @n)}"
    lines
  end

  def depth_lines
    lines = ['depth_selection']
    @depths.each do |entry|
      lines << "depth #{entry[:depth]} leaves #{entry[:leaves]} cv #{Evaluation.ratio(entry[:cv], @n)} train #{Evaluation.ratio(entry[:train], @n)} validation #{Evaluation.ratio(entry[:validation], @v)} test #{Evaluation.ratio(entry[:test], @m)}"
    end
    entry = @selected_depth
    lines << "selected depth #{entry[:depth]} leaves #{entry[:leaves]} test #{Evaluation.ratio(entry[:test], @m)}"
    lines
  end

  def complexity_lines
    lines = ['cost_complexity']
    @sequence.each do |item|
      entry = item[:entry]
      alpha = Evaluation.fraction(entry.alpha.numerator, entry.alpha.denominator, 6)
      lines << "subtree #{item[:index]} alpha #{alpha} leaves #{entry.leaves} train_errors #{entry.errors} validation_errors #{item[:validation_errors]}"
    end
    selected = @selected_sequence
    lines << "selected subtree #{selected[:index]} leaves #{selected[:entry].leaves} test #{Evaluation.ratio(correct_predictions(@models[:cost_complexity]), @m)}"
    lines
  end

  def bagging_lines
    lines = ["bagging trees #{@settings[:bag_trees]} seed #{@settings[:bag_seed]}"]
    @bags.each_with_index do |bag, index|
      lines << "bag #{index + 1} distinct #{bag[:distinct]} leaves #{bag[:leaves]} oob #{Evaluation.ratio(bag[:correct], bag[:size])}"
    end
    lines << "oob accuracy #{Evaluation.ratio(@oob_correct, @oob_voted)} unvoted #{@n - @oob_voted}"
    lines.concat(Evaluation.classification('bagging test', @test, @models[:bagging], @classes))
  end

  def mcnemar_lines
    lines = ['mcnemar pruned test']
    %i[grown depth cost_complexity bagging].each do |model|
      first = 0
      second = 0
      @test.each_with_index do |row, index|
        pruned_correct = @models[:pruned][index] == row.klass
        other_correct = @models[model][index] == row.klass
        first += 1 if pruned_correct && !other_correct
        second += 1 if other_correct && !pruned_correct
      end
      numerator = [0, (first - second).abs - 1].max**2
      denominator = first + second
      statistic = denominator.zero? ? '0/1 0.0000' : Evaluation.fraction(numerator, denominator)
      significant = 1000 * numerator > 3841 * denominator ? 'yes' : 'no'
      lines << "versus #{model} b #{first} c #{second} statistic #{statistic} significant #{significant}"
    end
    lines
  end

  def auc_lines
    %i[grown pruned bagging].map do |model|
      scores = if model == :bagging
                 @test_votes.map { |votes| [votes, @settings[:bag_trees]] }
               else
                 @routes[model].map { |route| [route.leaf.stats.counts, route.leaf.stats.size] }
               end
      fields = ['auc', model]
      macro = 0.0
      available = 0
      @classes.each_with_index do |name, klass|
        positive, negative = @test.each_index.partition { |index| @test[index].klass == klass }
        numerator = 0
        positive.each do |first|
          negative.each do |second|
            comparison = scores[first][0][klass] * scores[second][1] <=> scores[second][0][klass] * scores[first][1]
            numerator += 2 if comparison.positive?
            numerator += 1 if comparison.zero?
          end
        end
        denominator = 2 * positive.length * negative.length
        fields << name << Evaluation.fraction(numerator, denominator)
        unless denominator.zero?
          macro += numerator.to_f / denominator
          available += 1
        end
      end
      fields << 'macro' << (available.zero? ? '-' : Evaluation.real(macro / available))
      fields.join(' ')
    end
  end

  def learning_lines
    lines = ['learning_curve']
    @curve.each do |entry|
      lines << "size #{entry[:size]} grown leaves #{entry[:grown_leaves]} test #{Evaluation.ratio(entry[:grown_correct], @m)} pruned leaves #{entry[:pruned_leaves]} test #{Evaluation.ratio(entry[:pruned_correct], @m)}"
    end
    lines
  end

  def importance_lines(name, tree)
    lines = ["impurity #{name}"]
    impurity_importance(tree).each_with_index do |entry, index|
      lines << "#{index + 1} #{entry[:attribute].name} decrease #{Evaluation.real(entry[:decrease])} share #{entry[:share]} splits #{entry[:splits]}"
    end
    lines
  end

  def permutation_lines
    repeats = @settings[:permutation_repeats]
    lines = ["permutation pruned test repeats #{repeats} seed #{@settings[:permutation_seed]} base #{Evaluation.ratio(correct_predictions(@models[:pruned]), @m)}"]
    @permutations.each_with_index do |entry, index|
      lines << "#{index + 1} #{entry[:attribute].name} correct #{entry[:counts].join(' ')} drop #{Evaluation.fraction(entry[:drop], repeats * @m)}"
    end
    lines
  end

  def write_parts(name, parts)
    text = parts.map { |lines| lines.join("\n") }.join("\n\n") + "\n"
    File.binwrite(File.join('output', name), text)
  end

  def write_outputs
    Dir.mkdir('output') unless Dir.exist?('output')
    write_parts('tree.txt', [root_candidate_lines, tree_lines(@grown), surrogate_lines])
    write_parts('pruned_tree.txt', [pruning_lines, tree_lines(@pruned)])
    write_parts('predictions.csv', [prediction_lines])
    write_parts('rules.txt', [rule_lines, generalized_lines, misclassification_lines])
    evaluation = [data_lines, tree_summary_lines,
                  Evaluation.classification('grown test', @test, @models[:grown], @classes),
                  Evaluation.classification('pruned test', @test, @models[:pruned], @classes),
                  routing_lines, cross_validation_lines, depth_lines, complexity_lines,
                  bagging_lines, mcnemar_lines, auc_lines, learning_lines]
    write_parts('evaluation.txt', evaluation)
    write_parts('importance.txt', [importance_lines('grown', @grown),
                                   importance_lines('pruned', @pruned), permutation_lines])
  end

  def run
    build_primary_trees
    cross_validation
    cost_complexity_selection
    bagging
    build_rules
    learning_curve
    permutation_importance
    write_outputs
  end
end

DecisionTreeStudy.new.run if $PROGRAM_NAME == __FILE__
