include("dataset.jl")
include("impurity.jl")
include("tree_builder.jl")
include("evaluation.jl")
include("pruning.jl")

mutable struct Minstd
    state::Int
end

function draw!(generator)
    generator.state = mod(48271 * generator.state, 2147483647)
end

Base.@kwdef mutable struct Condition
    attribute::Attribute
    lower::Union{Nothing,Int} = nothing
    upper::Union{Nothing,Int} = nothing
    equal::Union{Nothing,Int} = nothing
    excluded::Set{Int} = Set{Int}()
end

mutable struct Rule
    number::Int
    leaf::Node
    conditions::Vector{Condition}
    general::Vector{Condition}
    removed::Vector{String}
end

struct DepthResult
    depth::Int
    tree::PrunedTree
    cv_correct::Int
end

struct Bag
    tree::PrunedTree
    distinct::Int
    out_of_bag::Int
    correct::Int
end

struct Permutation
    attribute::Attribute
    counts::Vector{Int}
    drop::Int
end

counts_text(counts) = join(counts, " ")
accuracy(tree, rows) = ratio_text(correct_count(tree, rows), length(rows))
ordered_average(values) = foldl(+, values; init=0.0) / length(values)
missing_count(row) = count(isnothing, row.values)

function join_sections(sections)
    lines = String[]
    for section in sections
        !isempty(lines) && push!(lines, "")
        append!(lines, section)
    end
    lines
end

function add_condition!(condition, split, left)
    if condition.attribute.integer
        if left
            condition.upper = isnothing(condition.upper) ? split.point : min(condition.upper, split.point)
        else
            condition.lower = isnothing(condition.lower) ? split.point : max(condition.lower, split.point)
        end
    elseif left
        condition.equal = split.point
    else
        push!(condition.excluded, split.point)
    end
end

function condition_text(condition)
    a = condition.attribute
    if a.integer
        if !isnothing(condition.lower) && !isnothing(condition.upper)
            return "$(half_text(condition.lower)) < $(a.name) <= $(half_text(condition.upper))"
        elseif !isnothing(condition.lower)
            return "$(a.name) > $(half_text(condition.lower))"
        end
        return "$(a.name) <= $(half_text(condition.upper))"
    end
    !isnothing(condition.equal) && return "$(a.name) = $(a.values[condition.equal])"
    names = a.values[sort(collect(condition.excluded))]
    length(names) == 1 ? "$(a.name) != $(names[1])" : "$(a.name) not in {$(join(names, ','))}"
end

function holds(condition, row)
    value = row.values[condition.attribute.index]
    isnothing(value) && return false
    if condition.attribute.integer
        return (isnothing(condition.lower) || 2 * value > condition.lower) && (isnothing(condition.upper) || 2 * value <= condition.upper)
    end
    isnothing(condition.equal) ? !(value in condition.excluded) : value == condition.equal
end

function simplify(steps, attributes)
    result = Condition[]
    for attribute in attributes
        related = [(split, left) for (split, left) in steps if split.attribute.index == attribute.index]
        isempty(related) && continue
        condition = Condition(; attribute)
        for (split, left) in related
            add_condition!(condition, split, left)
        end
        push!(result, condition)
    end
    result
end

conditions_text(conditions) = isempty(conditions) ? "true" : join(condition_text.(conditions), " and ")

function coverage(conditions, rows, label)
    covered = [row for row in rows if all(holds(condition, row) for condition in conditions)]
    count(row -> row.label == label, covered), length(covered)
end

function laplace(conditions, rows, label, class_count)
    hits, covered = coverage(conditions, rows, label)
    hits + 1, covered + class_count
end

function generalize(conditions, rows, label, class_count)
    current, removed = copy(conditions), String[]
    while !isempty(current)
        estimate = laplace(current, rows, label, class_count)
        best_index, best = 0, (0, 1)
        for index in eachindex(current)
            trial = laplace(current[setdiff(eachindex(current), [index])], rows, label, class_count)
            if best_index == 0 || is_greater(trial, best)
                best_index, best = index, trial
            end
        end
        is_greater(estimate, best) && break
        push!(removed, current[best_index].attribute.name)
        deleteat!(current, best_index)
    end
    current, removed
end

function build_rules(tree, attributes, validation, class_count)
    rules = Rule[]
    function collect_rules(node, steps)
        if is_leaf(tree, node)
            conditions = simplify(steps, attributes)
            general, removed = generalize(conditions, validation, node.prediction, class_count)
            push!(rules, Rule(length(rules) + 1, node, conditions, general, removed))
            return
        end
        collect_rules(node.left, [steps; [(node.split, true)]])
        collect_rules(node.right, [steps; [(node.split, false)]])
    end
    collect_rules(tree.root, Tuple{Split,Bool}[])
    rules
end

limited(tree, depth) = PrunedTree(tree.root, Set(node.number for node in internal_nodes(tree) if node.depth == depth))

function analyze(data)
    builder = TreeBuilder(data.attributes, length(data.classes), data.settings)
    grown = PrunedTree(grow(builder, data.train))
    pruned, decisions = reduced_error_pruning(grown.root, data.validation)
    rules = build_rules(pruned, data.attributes, data.validation, length(data.classes))
    n, f = length(data.train), data.settings.folds
    bounds = [div(fold * n, f) for fold in 0:f]
    folds = [data.train[bounds[fold]+1:bounds[fold+1]] for fold in 1:f]
    fold_trees = [PrunedTree(grow(builder, [data.train[1:bounds[fold]]; data.train[bounds[fold+1]+1:end]])) for fold in 1:f]
    depths = [DepthResult(depth, limited(grown, depth), sum(correct_count(limited(tree, depth), rows) for (tree, rows) in zip(fold_trees, folds))) for depth in 0:data.settings.max_depth]
    selected_depth = depths[findmax([result.cv_correct for result in depths])[2]]
    sequence = cost_complexity_sequence(grown.root)
    errors = [length(data.validation) - correct_count(step.tree, data.validation) for step in sequence]
    selected_index = findlast(==(minimum(errors)), errors)
    generator = Minstd(data.settings.bag_seed)
    bags = Bag[]
    oob_votes = [zeros(Int, length(data.classes)) for _ in data.train]
    for _ in 1:data.settings.bag_trees
        indices = [mod(draw!(generator), n) + 1 for _ in 1:n]
        tree = PrunedTree(grow(builder, data.train[indices]))
        sampled = Set(indices)
        oob = [index for index in 1:n if !(index in sampled)]
        correct = 0
        for index in oob
            prediction = predict(tree, data.train[index])
            oob_votes[index][prediction] += 1
            correct += prediction == data.train[index].label
        end
        push!(bags, Bag(tree, length(sampled), length(oob), correct))
    end
    test_votes = [zeros(Int, length(data.classes)) for _ in data.test]
    for bag in bags, (row, votes) in zip(data.test, test_votes)
        votes[predict(bag.tree, row)] += 1
    end
    models = Dict("grown" => grown, "pruned" => pruned, "depth" => selected_depth.tree, "cost_complexity" => sequence[selected_index].tree)
    predictions = Dict(name => [predict(tree, row) for row in data.test] for (name, tree) in models)
    predictions["bagging"] = majority.(test_votes)
    (; data, builder, grown, pruned, decisions, rules, bounds, folds, fold_trees, depths, selected_depth, sequence, selected_index, bags, oob_votes, test_votes, predictions)
end

function tree_lines(a, tree)
    lines = String[]
    function visit(node, condition)
        line = "$("  "^node.depth)$(node.number) $condition n $(node.size) counts $(counts_text(node.counts))"
        if is_leaf(tree, node)
            push!(lines, "$line leaf $(a.data.classes[node.prediction])")
        else
            push!(lines, line)
            visit(node.left, split_text(node.split))
            visit(node.right, split_text(node.split, false))
        end
    end
    visit(tree.root, "root")
    nodes, terminal = preorder(tree), leaves(tree)
    depth = tree_depth(tree)
    push!(lines, "", "nodes $(length(nodes)) leaves $(length(terminal)) depth $depth errors $(ratio_text(training_errors(tree), length(a.data.train)))")
    for level in 0:depth
        at_level = [node for node in terminal if node.depth == level]
        rows = sum((node.size for node in at_level); init=0)
        errors = sum((node.errors for node in at_level); init=0)
        push!(lines, "level $level nodes $(count(node -> node.depth == level, nodes)) leaves $(length(at_level)) rows $rows errors $errors")
    end
    lines
end

function root_candidate_lines(a)
    n, counts = length(a.data.train), a.grown.root.counts
    found = Candidate[]
    for attribute in a.data.attributes
        candidate = best_split(a.builder, a.data.train, [attribute])
        !isnothing(candidate) && push!(found, candidate)
    end
    sort!(found; lt=(first, second) -> is_greater(candidate_value(first), candidate_value(second)) || (!is_greater(candidate_value(second), candidate_value(first)) && first.split.attribute.index < second.split.attribute.index))
    lines = ["root candidates n $n counts $(counts_text(counts))"]
    for (rank, candidate) in enumerate(found)
        numerator, denominator = candidate_value(candidate)
        gain = numerator / denominator / n - square_sum(counts) / (n * n)
        push!(lines, "$rank $(split_text(candidate.split)) left $(sum(candidate.left)) right $(sum(candidate.right)) gain $(real_text(gain, 6))")
    end
    lines
end

function surrogate_lines(a)
    lines = ["surrogates"]
    for node in internal_nodes(a.grown)
        parts = ["$(split_text(s.split)) $(s.left ? "left" : "right") $(s.score)/$(node.size)" for s in node.surrogates]
        listed = isempty(parts) ? "none" : join(parts, " ; ")
        push!(lines, "node $(node.number) split $(split_text(node.split)) default $(node.default_left ? "left" : "right") surrogates $listed")
    end
    lines
end

function pruned_tree_file(a)
    lines = ["reduced_error_pruning validation $(length(a.data.validation))"]
    for decision in a.decisions
        push!(lines, "node $(decision.node.number) depth $(decision.node.depth) rows $(decision.rows) leaf $(decision.leaf_error) subtree $(decision.subtree_error) $(decision.pruned ? "pruned" : "kept")")
    end
    removed = count(d -> d.pruned, a.decisions)
    examined = length(a.decisions)
    push!(lines, "examined $examined pruned $removed kept $(examined - removed)", "")
    append!(lines, tree_lines(a, a.pruned))
    lines
end

function predictions_file(a)
    lines, classes = ["id,predicted,actual,grown,leaf,path,missing"], a.data.classes
    for row in a.data.test
        path, methods = route(a.pruned, row)
        leaf = last(path)
        push!(lines, join([row.id, classes[leaf.prediction], classes[row.label], classes[predict(a.grown, row)], string(leaf.number), join([node.number for node in path], '-'), string(count(!=(1), methods))], ','))
    end
    lines
end

function rules_file(a)
    data, classes = a.data, a.data.classes
    ordinary, generalized = ["rules $(length(a.rules))"], ["generalized $(length(a.rules))"]
    for rule in a.rules
        label = rule.leaf.prediction
        reached = [row for row in data.test if leaf_of(a.pruned, row).number == rule.leaf.number]
        hits = count(row -> row.label == label, reached)
        push!(ordinary, "rule $(rule.number) node $(rule.leaf.number) if $(conditions_text(rule.conditions)) then $(classes[label]) train $(ratio_text(maximum(rule.leaf.counts), rule.leaf.size)) test $(ratio_text(hits, length(reached)))")
        hits, covered = coverage(rule.general, data.validation, label)
        test_hits, test_covered = coverage(rule.general, data.test, label)
        removed = isempty(rule.removed) ? "none" : join(rule.removed, ',')
        push!(generalized, "general $(rule.number) if $(conditions_text(rule.general)) then $(classes[label]) removed $removed laplace $(fraction_text(hits + 1, covered + length(classes))) validation $hits/$covered test $test_hits/$test_covered")
    end
    wrong = [row for row in data.test if predict(a.pruned, row) != row.label]
    explanations = ["misclassified $(length(wrong))"]
    rule_numbers = Dict(rule.leaf.number => rule.number for rule in a.rules)
    marks = ("", " [surrogate]", " [default]")
    for row in wrong
        path, methods = route(a.pruned, row)
        parts = [split_text(path[index].split, path[index + 1].number == path[index].left.number) * marks[method] for (index, method) in enumerate(methods)]
        text = isempty(parts) ? "root" : join(parts, "; ")
        leaf = last(path)
        push!(explanations, "$(row.id) actual $(classes[row.label]) predicted $(classes[leaf.prediction]) rule $(rule_numbers[leaf.number]) path $text")
    end
    join_sections([ordinary, generalized, explanations])
end

function data_lines(a)
    data = a.data
    lines = ["data train $(length(data.train)) validation $(length(data.validation)) test $(length(data.test)) attributes $(length(data.attributes)) classes $(length(data.classes)) target $(data.target)"]
    train, validation, test = [class_counts(rows, length(data.classes)) for rows in (data.train, data.validation, data.test)]
    for (label, name) in enumerate(data.classes)
        push!(lines, "class $name train $(train[label]) validation $(validation[label]) test $(test[label])")
    end
    push!(lines, "missing validation $(sum(missing_count, data.validation)) test $(sum(missing_count, data.test))")
    for attribute in data.attributes
        v = count(row -> isnothing(row.values[attribute.index]), data.validation)
        t = count(row -> isnothing(row.values[attribute.index]), data.test)
        push!(lines, "missing $(attribute.name) validation $v test $t")
    end
    lines
end

summary_line(a, name, tree) = "$name nodes $(length(preorder(tree))) leaves $(length(leaves(tree))) depth $(tree_depth(tree)) train $(accuracy(tree, a.data.train)) validation $(accuracy(tree, a.data.validation)) test $(accuracy(tree, a.data.test))"
model_evaluation(a, name) = classification_lines("$name test", a.data.classes, [row.label for row in a.data.test], a.predictions[name])

function routing_lines(a)
    internal = internal_nodes(a.pruned)
    tallies = Dict(node.number => zeros(Int, 3) for node in internal)
    for row in a.data.test
        path, methods = route(a.pruned, row)
        for (node, method) in zip(path, methods)
            tallies[node.number][method] += 1
        end
    end
    lines = ["routing pruned test"]
    for node in internal
        tally = tallies[node.number]
        push!(lines, "node $(node.number) rows $(sum(tally)) primary $(tally[1]) surrogate $(tally[2]) default $(tally[3])")
    end
    for (name, complete) in (("complete", true), ("incomplete", false))
        rows = [row for row in a.data.test if (missing_count(row) == 0) == complete]
        push!(lines, "$name rows $(length(rows)) correct $(accuracy(a.pruned, rows))")
    end
    lines
end

function cross_validation_lines(a)
    lines = ["cross_validation folds $(a.data.settings.folds)"]
    total = 0
    for (fold, (tree, rows)) in enumerate(zip(a.fold_trees, a.folds))
        correct = correct_count(tree, rows)
        total += correct
        push!(lines, "fold $fold rows $(a.bounds[fold] + 1)-$(a.bounds[fold + 1]) leaves $(length(leaves(tree))) correct $(ratio_text(correct, length(rows)))")
    end
    push!(lines, "cv accuracy $(ratio_text(total, length(a.data.train)))")
    lines
end

function depth_lines(a)
    lines = ["depth_selection"]
    for result in a.depths
        tree = result.tree
        push!(lines, "depth $(result.depth) leaves $(length(leaves(tree))) cv $(ratio_text(result.cv_correct, length(a.data.train))) train $(accuracy(tree, a.data.train)) validation $(accuracy(tree, a.data.validation)) test $(accuracy(tree, a.data.test))")
    end
    selected = a.selected_depth
    push!(lines, "selected depth $(selected.depth) leaves $(length(leaves(selected.tree))) test $(accuracy(selected.tree, a.data.test))")
    lines
end

function cost_complexity_lines(a)
    lines = ["cost_complexity"]
    for (index, step) in enumerate(a.sequence)
        numerator, denominator = step.alpha
        push!(lines, "subtree $(index - 1) alpha $(fraction_text(numerator, denominator * length(a.data.train), 6)) leaves $(length(leaves(step.tree))) train_errors $(training_errors(step.tree)) validation_errors $(length(a.data.validation) - correct_count(step.tree, a.data.validation))")
    end
    selected = a.sequence[a.selected_index].tree
    push!(lines, "selected subtree $(a.selected_index - 1) leaves $(length(leaves(selected))) test $(accuracy(selected, a.data.test))")
    lines
end

function bagging_lines(a)
    options = a.data.settings
    lines = ["bagging trees $(options.bag_trees) seed $(options.bag_seed)"]
    for (number, bag) in enumerate(a.bags)
        push!(lines, "bag $number distinct $(bag.distinct) leaves $(length(leaves(bag.tree))) oob $(ratio_text(bag.correct, bag.out_of_bag))")
    end
    voted = hits = 0
    for (row, votes) in zip(a.data.train, a.oob_votes)
        if sum(votes) > 0
            voted += 1
            hits += majority(votes) == row.label
        end
    end
    push!(lines, "oob accuracy $(ratio_text(hits, voted)) unvoted $(length(a.data.train) - voted)")
    append!(lines, model_evaluation(a, "bagging"))
    lines
end

function mcnemar_lines(a)
    lines = ["mcnemar pruned test"]
    pruned = [prediction == row.label for (prediction, row) in zip(a.predictions["pruned"], a.data.test)]
    for name in ("grown", "depth", "cost_complexity", "bagging")
        other = [prediction == row.label for (prediction, row) in zip(a.predictions[name], a.data.test)]
        b = count(first && !second for (first, second) in zip(pruned, other))
        c = count(second && !first for (first, second) in zip(pruned, other))
        u = max(0, abs(b - c) - 1)^2
        statistic = b + c == 0 ? "0/1 0.0000" : fraction_text(u, b + c)
        significant = 1000 * u > 3841 * (b + c) ? "yes" : "no"
        push!(lines, "versus $name b $b c $c statistic $statistic significant $significant")
    end
    lines
end

function auc_lines(a)
    lines = String[]
    for name in ("grown", "pruned", "bagging")
        scores = Vector{Tuple{Int,Int}}[]
        for (index, row) in enumerate(a.data.test)
            if name == "bagging"
                push!(scores, [(votes, a.data.settings.bag_trees) for votes in a.test_votes[index]])
            else
                leaf = leaf_of(name == "grown" ? a.grown : a.pruned, row)
                push!(scores, [(count, leaf.size) for count in leaf.counts])
            end
        end
        parts, values = ["auc", name], Float64[]
        for (label, class_name) in enumerate(a.data.classes)
            positives = [scores[index][label] for (index, row) in enumerate(a.data.test) if row.label == label]
            negatives = [scores[index][label] for (index, row) in enumerate(a.data.test) if row.label != label]
            wins = 0
            for first in positives, second in negatives
                wins += is_greater(first, second) ? 2 : !is_greater(second, first) ? 1 : 0
            end
            pairs = 2 * length(positives) * length(negatives)
            append!(parts, [class_name, fraction_text(wins, pairs)])
            pairs > 0 && push!(values, wins / pairs)
        end
        append!(parts, ["macro", isempty(values) ? "-" : real_text(ordered_average(values))])
        push!(lines, join(parts, " "))
    end
    lines
end

function learning_curve_lines(a)
    lines = ["learning_curve"]
    for size in a.data.settings.curve
        grown = PrunedTree(grow(a.builder, a.data.train[1:size]))
        pruned, _ = reduced_error_pruning(grown.root, a.data.validation)
        push!(lines, "size $size grown leaves $(length(leaves(grown))) test $(accuracy(grown, a.data.test)) pruned leaves $(length(leaves(pruned))) test $(accuracy(pruned, a.data.test))")
    end
    lines
end

function evaluation_file(a)
    join_sections([data_lines(a), [summary_line(a, "grown", a.grown), summary_line(a, "pruned", a.pruned)],
        model_evaluation(a, "grown"), model_evaluation(a, "pruned"), routing_lines(a), cross_validation_lines(a),
        depth_lines(a), cost_complexity_lines(a), bagging_lines(a), mcnemar_lines(a), auc_lines(a), learning_curve_lines(a)])
end

function impurity_lines(a, title, tree)
    importance = zeros(Float64, length(a.data.attributes))
    splits = zeros(Int, length(importance))
    for node in internal_nodes(tree)
        index = node.split.attribute.index
        importance[index] += impurity_decrease(node.counts, node.left.counts, node.right.counts)
        splits[index] += 1
    end
    total = foldl(+, importance; init=0.0)
    shares = total == 0 ? zeros(length(importance)) : importance ./ total
    order = sort(collect(eachindex(importance)); by=index -> (-round(shares[index]; digits=4), index))
    lines = ["impurity $title"]
    for (rank, index) in enumerate(order)
        push!(lines, "$rank $(a.data.attributes[index].name) decrease $(real_text(importance[index] / length(a.data.train))) share $(real_text(shares[index])) splits $(splits[index])")
    end
    lines
end

function permutation_lines(a)
    options = a.data.settings
    generator, repeats, size = Minstd(options.permutation_seed), options.permutation_repeats, length(a.data.test)
    base = correct_count(a.pruned, a.data.test)
    results = Permutation[]
    for attribute in a.data.attributes
        counts = Int[]
        for _ in 1:repeats
            values = [row.values[attribute.index] for row in a.data.test]
            for position in size:-1:2
                other = mod(draw!(generator), position) + 1
                values[position], values[other] = values[other], values[position]
            end
            rows = Row[]
            for (row, value) in zip(a.data.test, values)
                changed = copy(row.values)
                changed[attribute.index] = value
                push!(rows, Row(row.id, changed, row.label))
            end
            push!(counts, correct_count(a.pruned, rows))
        end
        push!(results, Permutation(attribute, counts, repeats * base - sum(counts)))
    end
    sort!(results; by=result -> (-result.drop, result.attribute.index))
    lines = ["permutation pruned test repeats $repeats seed $(options.permutation_seed) base $(ratio_text(base, size))"]
    for (rank, result) in enumerate(results)
        push!(lines, "$rank $(result.attribute.name) correct $(counts_text(result.counts)) drop $(fraction_text(result.drop, repeats * size))")
    end
    lines
end

function main()
    a = analyze(load_dataset("input"))
    mkpath("output")
    files = [("tree.txt", join_sections([root_candidate_lines(a), tree_lines(a, a.grown), surrogate_lines(a)])),
        ("pruned_tree.txt", pruned_tree_file(a)), ("predictions.csv", predictions_file(a)), ("rules.txt", rules_file(a)),
        ("evaluation.txt", evaluation_file(a)), ("importance.txt", join_sections([impurity_lines(a, "grown", a.grown), impurity_lines(a, "pruned", a.pruned), permutation_lines(a)]))]
    for (name, lines) in files
        open(joinpath("output", name), "w") do file
            for line in lines
                println(file, line)
            end
        end
    end
end

main()
