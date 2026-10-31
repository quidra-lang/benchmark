using Printf

struct PrunedTree
    root::Node
    cut::Set{Int}
end

PrunedTree(root) = PrunedTree(root, Set{Int}())
is_leaf(tree, node) = isnothing(node.split) || node.number in tree.cut

function real_text(value, places=4)
    text = Printf.format(Printf.Format("%.$(places)f"), value)
    text == "-0." * "0"^places ? text[2:end] : text
end

ratio_text(a, b) = b == 0 ? "0/0 -" : "$a/$b $(real_text(a / b))"

function fraction_text(a, b, places=4)
    b == 0 && return "- -"
    divisor = gcd(a, b)
    numerator, denominator = div(a, divisor), div(b, divisor)
    "$numerator/$denominator $(real_text(numerator / denominator, places))"
end

function direction(node, row)
    value = row.values[node.split.attribute.index]
    !isnothing(value) && return (goes_left(node.split, value), 1)
    for surrogate in node.surrogates
        value = row.values[surrogate.split.attribute.index]
        !isnothing(value) && return (goes_left(surrogate.split, value) == surrogate.left, 2)
    end
    node.default_left, 3
end

function preorder(tree, start=tree.root)
    result, pending = Node[], [start]
    while !isempty(pending)
        node = pop!(pending)
        push!(result, node)
        if !is_leaf(tree, node)
            push!(pending, node.right, node.left)
        end
    end
    result
end

leaves(tree, start=tree.root) = [node for node in preorder(tree, start) if is_leaf(tree, node)]
internal_nodes(tree) = [node for node in preorder(tree) if !is_leaf(tree, node)]
tree_depth(tree) = maximum(node.depth for node in leaves(tree))
training_errors(tree) = sum(node.errors for node in leaves(tree))

function route(tree, row)
    node = tree.root
    path, methods = [node], Int[]
    while !is_leaf(tree, node)
        left, method = direction(node, row)
        node = left ? node.left : node.right
        push!(path, node)
        push!(methods, method)
    end
    path, methods
end

leaf_of(tree, row) = last(first(route(tree, row)))
predict(tree, row) = leaf_of(tree, row).prediction
correct_count(tree, rows) = count(row -> predict(tree, row) == row.label, rows)

function classification_lines(title, classes, actual, predicted)
    matrix = zeros(Int, length(classes), length(classes))
    for (label, prediction) in zip(actual, predicted)
        matrix[label, prediction] += 1
    end
    correct = sum(matrix[i, i] for i in eachindex(classes))
    total = length(actual)
    lines = ["confusion $title correct $correct/$total accuracy $(fraction_text(correct, total))", "actual\\predicted " * join(classes, " ")]
    for (index, name) in enumerate(classes)
        push!(lines, name * " " * join(matrix[index, :], " "))
    end
    values = Float64[]
    for (index, name) in enumerate(classes)
        hits = matrix[index, index]
        predicted_total, support = sum(matrix[:, index]), sum(matrix[index, :])
        predicted_total + support > 0 && push!(values, 2 * hits / (predicted_total + support))
        push!(lines, "class $name precision $(fraction_text(hits, predicted_total)) recall $(fraction_text(hits, support)) f1 $(fraction_text(2 * hits, predicted_total + support)) support $support")
    end
    push!(lines, "macro_f1 $(real_text(foldl(+, values; init=0.0) / length(values)))")
    lines
end
