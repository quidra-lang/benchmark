local evaluation = require("evaluation")
local impurity = require("impurity")
local M = {}

function M.reduced_error(root, rows)
    local original, reached, errors = evaluation.view(root), {}, {}
    for _, row in ipairs(rows) do
        for _, node in ipairs(original:route(row).path) do
            reached[node.number] = (reached[node.number] or 0) + 1
            if row.label ~= node.prediction then errors[node.number] = (errors[node.number] or 0) + 1 end
        end
    end
    local cut, decisions = {}, {}
    local function visit(node)
        local leaf_error = errors[node.number] or 0
        if not node.split then return leaf_error end
        local left_error = visit(node.left)
        local subtree_error = left_error + visit(node.right)
        local pruned = leaf_error <= subtree_error
        if pruned then cut[node.number] = true end
        decisions[#decisions + 1] = {node = node, rows = reached[node.number] or 0,
            leaf_error = leaf_error, subtree_error = subtree_error, pruned = pruned}
        return pruned and leaf_error or subtree_error
    end
    visit(root)
    return evaluation.view(root, cut), decisions
end

function M.cost_complexity(root)
    local tree = evaluation.view(root)
    local sequence = {{alpha = {0, 1}, tree = tree}}
    while not tree:is_leaf(root) do
        local alpha, weakest
        for _, node in ipairs(tree:internal_nodes()) do
            local leaves, errors = tree:leaves(node), 0
            for _, leaf in ipairs(leaves) do errors = errors + leaf.errors end
            local value = {node.errors - errors, #leaves - 1}
            local comparison = alpha and impurity.compare(value, alpha) or -1
            if comparison < 0 then alpha, weakest = value, {[node.number] = true}
            elseif comparison == 0 then weakest[node.number] = true end
        end
        local cut = {}
        for number in pairs(tree.cut) do cut[number] = true end
        for number in pairs(weakest) do cut[number] = true end
        tree = evaluation.view(root, cut)
        sequence[#sequence + 1] = {alpha = alpha, tree = tree}
    end
    return sequence
end

return M
