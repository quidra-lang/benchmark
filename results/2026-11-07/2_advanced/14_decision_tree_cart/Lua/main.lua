local source_dir = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_dir .. "?.lua;" .. package.path

local dataset = require("dataset")
local impurity = require("impurity")
local builder_module = require("tree_builder")
local pruning = require("pruning")
local evaluation = require("evaluation")
local format = string.format

local function append(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
end

local function copy(values)
    local result = {}
    append(result, values)
    return result
end

local function slice(values, first, last)
    local result = {}
    for index = first, last do result[#result + 1] = values[index] end
    return result
end

local function count_keys(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function join_sections(sections)
    local result = {}
    for index, section in ipairs(sections) do
        if index > 1 then result[#result + 1] = "" end
        append(result, section)
    end
    return result
end

local function minstd(seed)
    return function()
        seed = 48271 * seed % 2147483647
        return seed
    end
end

local Condition = {}
Condition.__index = Condition

function Condition.new(attribute)
    return setmetatable({attribute = attribute, excluded = {}}, Condition)
end

function Condition:add(split, left)
    if self.attribute.integer then
        if left then self.upper = self.upper and math.min(self.upper, split.point) or split.point
        else self.lower = self.lower and math.max(self.lower, split.point) or split.point end
    elseif left then self.equal = split.point
    else self.excluded[split.point] = true end
end

function Condition:text()
    local name, half = self.attribute.name, builder_module.half_text
    if self.attribute.integer then
        if self.lower and self.upper then return half(self.lower) .. " < " .. name .. " <= " .. half(self.upper) end
        if self.lower then return name .. " > " .. half(self.lower) end
        return name .. " <= " .. half(self.upper)
    end
    if self.equal then return name .. " = " .. self.attribute.values[self.equal] end
    local names = {}
    for index, value in ipairs(self.attribute.values) do
        if self.excluded[index] then names[#names + 1] = value end
    end
    if #names == 1 then return name .. " != " .. names[1] end
    return name .. " not in {" .. table.concat(names, ",") .. "}"
end

function Condition:holds(row)
    local value = row.values[self.attribute.index]
    if value == false then return false end
    if self.attribute.integer then
        return (not self.lower or 2 * value > self.lower) and (not self.upper or 2 * value <= self.upper)
    end
    if self.equal then return value == self.equal end
    return not self.excluded[value]
end

local function conditions_text(conditions)
    if #conditions == 0 then return "true" end
    local parts = {}
    for _, condition in ipairs(conditions) do parts[#parts + 1] = condition:text() end
    return table.concat(parts, " and ")
end

local function coverage(conditions, rows, label)
    local hits, covered = 0, 0
    for _, row in ipairs(rows) do
        local holds = true
        for _, condition in ipairs(conditions) do
            if not condition:holds(row) then holds = false; break end
        end
        if holds then
            covered = covered + 1
            if row.label == label then hits = hits + 1 end
        end
    end
    return hits, covered
end

local function generalize(conditions, rows, label, class_count)
    local current, removed = copy(conditions), {}
    while #current > 0 do
        local hits, covered = coverage(current, rows, label)
        local estimate, best, best_index = {hits + 1, covered + class_count}
        for index = 1, #current do
            local trial = copy(current)
            table.remove(trial, index)
            local h, c = coverage(trial, rows, label)
            local value = {h + 1, c + class_count}
            if not best or impurity.compare(value, best) > 0 then best, best_index = value, index end
        end
        if impurity.compare(estimate, best) > 0 then break end
        removed[#removed + 1] = current[best_index].attribute.name
        table.remove(current, best_index)
    end
    return current, removed
end

local function missing_count(row)
    local count = 0
    for _, value in ipairs(row.values) do if value == false then count = count + 1 end end
    return count
end

local function training_errors(tree)
    local total = 0
    for _, leaf in ipairs(tree:leaves()) do total = total + leaf.errors end
    return total
end

local function tree_depth(tree)
    local depth = 0
    for _, leaf in ipairs(tree:leaves()) do depth = math.max(depth, leaf.depth) end
    return depth
end

local function limited(tree, depth)
    local cut = {}
    for _, node in ipairs(tree:internal_nodes()) do
        if node.depth == depth then cut[node.number] = true end
    end
    return evaluation.view(tree.root, cut)
end

local Study = {}
Study.__index = Study

function Study.new(data)
    local self = setmetatable({data = data, attributes = data.attributes, classes = data.classes,
        train = data.train, validation = data.validation, test = data.test, settings = data.settings}, Study)
    self.builder = builder_module.new(self.attributes, #self.classes, self.settings)
    self.grown = evaluation.view(self.builder:grow(self.train))
    self.pruned, self.decisions = pruning.reduced_error(self.grown.root, self.validation)
    self:build_rules()
    self.bounds, self.fold_trees = {}, {}
    for fold = 0, self.settings.folds do self.bounds[fold + 1] = fold * #self.train // self.settings.folds end
    for fold = 1, self.settings.folds do
        local rows = slice(self.train, 1, self.bounds[fold])
        append(rows, slice(self.train, self.bounds[fold + 1] + 1, #self.train))
        self.fold_trees[fold] = evaluation.view(self.builder:grow(rows))
    end
    self.depth_results = {}
    for depth = 0, self.settings.max_depth do
        local correct = 0
        for fold, tree in ipairs(self.fold_trees) do correct = correct + limited(tree, depth):correct_count(self:fold_rows(fold)) end
        local result = {depth = depth, tree = limited(self.grown, depth), cv = correct}
        self.depth_results[#self.depth_results + 1] = result
        if not self.selected_depth or correct > self.selected_depth.cv then self.selected_depth = result end
    end
    self.sequence = pruning.cost_complexity(self.grown.root)
    self.selected_index = 1
    for index, step in ipairs(self.sequence) do
        if self:validation_errors(step.tree) <= self:validation_errors(self.sequence[self.selected_index].tree) then
            self.selected_index = index
        end
    end
    self:bagging()
    self.predictions = {}
    local models = {grown = self.grown, pruned = self.pruned, depth = self.selected_depth.tree,
        cost_complexity = self.sequence[self.selected_index].tree}
    for name, tree in pairs(models) do
        local predictions = {}
        for _, row in ipairs(self.test) do predictions[#predictions + 1] = tree:predict(row) end
        self.predictions[name] = predictions
    end
    self.predictions.bagging = {}
    for _, votes in ipairs(self.test_votes) do self.predictions.bagging[#self.predictions.bagging + 1] = impurity.majority(votes) end
    return self
end

function Study:accuracy(tree, rows)
    return evaluation.ratio(tree:correct_count(rows), #rows)
end

function Study:fold_rows(fold)
    return slice(self.train, self.bounds[fold] + 1, self.bounds[fold + 1])
end

function Study:validation_errors(tree)
    return #self.validation - tree:correct_count(self.validation)
end

function Study:build_rules()
    self.rules = {}
    local function collect(node, steps)
        if self.pruned:is_leaf(node) then
            local conditions = {}
            for _, attribute in ipairs(self.attributes) do
                local condition
                for _, step in ipairs(steps) do
                    if step.split.attribute == attribute then
                        condition = condition or Condition.new(attribute)
                        condition:add(step.split, step.left)
                    end
                end
                if condition then conditions[#conditions + 1] = condition end
            end
            local general, removed = generalize(conditions, self.validation, node.prediction, #self.classes)
            self.rules[#self.rules + 1] = {number = #self.rules + 1, leaf = node, label = node.prediction,
                conditions = conditions, general = general, removed = removed}
            return
        end
        local left, right = copy(steps), copy(steps)
        left[#left + 1] = {split = node.split, left = true}
        right[#right + 1] = {split = node.split, left = false}
        collect(node.left, left)
        collect(node.right, right)
    end
    collect(self.pruned.root, {})
end

function Study:bagging()
    local draw, size = minstd(self.settings.bag_seed), #self.train
    self.bags, self.oob_votes, self.test_votes = {}, {}, {}
    local function zero_votes()
        local votes = {}
        for label = 1, #self.classes do votes[label] = 0 end
        return votes
    end
    for index = 1, size do self.oob_votes[index] = zero_votes() end
    for index = 1, #self.test do self.test_votes[index] = zero_votes() end
    for _ = 1, self.settings.bag_trees do
        local sample, sampled = {}, {}
        for _ = 1, size do
            local index = draw() % size + 1
            sample[#sample + 1], sampled[index] = self.train[index], true
        end
        local tree = evaluation.view(self.builder:grow(sample))
        local out_of_bag, correct = 0, 0
        for index, row in ipairs(self.train) do
            if not sampled[index] then
                out_of_bag = out_of_bag + 1
                local prediction = tree:predict(row)
                self.oob_votes[index][prediction] = self.oob_votes[index][prediction] + 1
                if prediction == row.label then correct = correct + 1 end
            end
        end
        for index, row in ipairs(self.test) do
            local prediction = tree:predict(row)
            self.test_votes[index][prediction] = self.test_votes[index][prediction] + 1
        end
        self.bags[#self.bags + 1] = {tree = tree, distinct = count_keys(sampled), out_of_bag = out_of_bag, correct = correct}
    end
end

function Study:tree_lines(tree)
    local lines = {}
    local function visit(node, condition)
        local text = string.rep("  ", node.depth) .. format("%d %s n %d counts %s", node.number, condition, node.size, table.concat(node.counts, " "))
        if tree:is_leaf(node) then text = text .. " leaf " .. self.classes[node.prediction] end
        lines[#lines + 1] = text
        if not tree:is_leaf(node) then
            visit(node.left, node.split:condition(true))
            visit(node.right, node.split:condition(false))
        end
    end
    visit(tree.root, "root")
    lines[#lines + 1] = ""
    local nodes, leaves, depth = tree:preorder(), tree:leaves(), tree_depth(tree)
    lines[#lines + 1] = format("nodes %d leaves %d depth %d errors %s", #nodes, #leaves, depth, evaluation.ratio(training_errors(tree), #self.train))
    for level = 0, depth do
        local n, l, rows, errors = 0, 0, 0, 0
        for _, node in ipairs(nodes) do if node.depth == level then n = n + 1 end end
        for _, leaf in ipairs(leaves) do
            if leaf.depth == level then l, rows, errors = l + 1, rows + leaf.size, errors + leaf.errors end
        end
        lines[#lines + 1] = format("level %d nodes %d leaves %d rows %d errors %d", level, n, l, rows, errors)
    end
    return lines
end

function Study:tree_file()
    local found = {}
    for _, attribute in ipairs(self.attributes) do
        local candidate = self.builder:best_split(self.train, {attribute})
        if candidate then found[#found + 1] = candidate end
    end
    table.sort(found, function(a, b)
        local comparison = impurity.compare(a.value, b.value)
        if comparison ~= 0 then return comparison > 0 end
        return a.split.attribute.index < b.split.attribute.index
    end)
    local root, size = self.grown.root, #self.train
    local candidates = {format("root candidates n %d counts %s", size, table.concat(root.counts, " "))}
    for rank, candidate in ipairs(found) do
        local gain = candidate.value[1] / candidate.value[2] / size - impurity.square_sum(root.counts) / (size * size)
        candidates[#candidates + 1] = format("%d %s left %d right %d gain %s", rank, candidate.split:condition(true),
            #candidate.left, #candidate.right, evaluation.real(gain, 6))
    end
    local surrogates = {"surrogates"}
    for _, node in ipairs(self.grown:internal_nodes()) do
        local listed = {}
        for _, surrogate in ipairs(node.surrogates) do
            listed[#listed + 1] = format("%s %s %d/%d", surrogate.split:condition(true), surrogate.direction, surrogate.score, node.size)
        end
        surrogates[#surrogates + 1] = format("node %d split %s default %s surrogates %s", node.number,
            node.split:condition(true), node.default, #listed > 0 and table.concat(listed, " ; ") or "none")
    end
    return join_sections({candidates, self:tree_lines(self.grown), surrogates})
end

function Study:pruned_tree_file()
    local lines, pruned = {"reduced_error_pruning validation " .. #self.validation}, 0
    for _, decision in ipairs(self.decisions) do
        if decision.pruned then pruned = pruned + 1 end
        lines[#lines + 1] = format("node %d depth %d rows %d leaf %d subtree %d %s", decision.node.number,
            decision.node.depth, decision.rows, decision.leaf_error, decision.subtree_error, decision.pruned and "pruned" or "kept")
    end
    lines[#lines + 1] = format("examined %d pruned %d kept %d", #self.decisions, pruned, #self.decisions - pruned)
    return join_sections({lines, self:tree_lines(self.pruned)})
end

function Study:predictions_file()
    local lines = {"id,predicted,actual,grown,leaf,path,missing"}
    for index, row in ipairs(self.test) do
        local route, path, missing = self.pruned:route(row), {}, 0
        for _, node in ipairs(route.path) do path[#path + 1] = node.number end
        for _, step in ipairs(route.steps) do if step.method ~= "primary" then missing = missing + 1 end end
        lines[#lines + 1] = table.concat({row.id, self.classes[route.leaf.prediction], self.classes[row.label],
            self.classes[self.predictions.grown[index]], route.leaf.number, table.concat(path, "-"), missing}, ",")
    end
    return lines
end

function Study:rules_file()
    local original, generalized, mistakes, rule_numbers = {"rules " .. #self.rules}, {"generalized " .. #self.rules}, {}, {}
    for _, rule in ipairs(self.rules) do
        rule_numbers[rule.leaf.number] = rule.number
        local rows, hits = 0, 0
        for _, row in ipairs(self.test) do
            if self.pruned:route(row).leaf == rule.leaf then
                rows = rows + 1
                if row.label == rule.label then hits = hits + 1 end
            end
        end
        original[#original + 1] = format("rule %d node %d if %s then %s train %s test %s", rule.number,
            rule.leaf.number, conditions_text(rule.conditions), self.classes[rule.label],
            evaluation.ratio(rule.leaf.counts[rule.label], rule.leaf.size), evaluation.ratio(hits, rows))
        local vh, vc = coverage(rule.general, self.validation, rule.label)
        local th, tc = coverage(rule.general, self.test, rule.label)
        generalized[#generalized + 1] = format("general %d if %s then %s removed %s laplace %s validation %d/%d test %d/%d",
            rule.number, conditions_text(rule.general), self.classes[rule.label], #rule.removed > 0 and table.concat(rule.removed, ",") or "none",
            evaluation.fraction(vh + 1, vc + #self.classes), vh, vc, th, tc)
    end
    for _, row in ipairs(self.test) do
        local route = self.pruned:route(row)
        if route.leaf.prediction ~= row.label then
            local parts = {}
            for _, step in ipairs(route.steps) do
                parts[#parts + 1] = step.node.split:condition(step.left) .. (step.method == "primary" and "" or " [" .. step.method .. "]")
            end
            mistakes[#mistakes + 1] = format("%s actual %s predicted %s rule %d path %s", row.id, self.classes[row.label],
                self.classes[route.leaf.prediction], rule_numbers[route.leaf.number], #parts > 0 and table.concat(parts, "; ") or "root")
        end
    end
    local wrong = {"misclassified " .. #mistakes}
    append(wrong, mistakes)
    return join_sections({original, generalized, wrong})
end

function Study:data_lines()
    local lines = {format("data train %d validation %d test %d attributes %d classes %d target %s", #self.train,
        #self.validation, #self.test, #self.attributes, #self.classes, self.data.target)}
    local tr, va, te = impurity.class_counts(self.train, #self.classes), impurity.class_counts(self.validation, #self.classes), impurity.class_counts(self.test, #self.classes)
    for label, name in ipairs(self.classes) do lines[#lines + 1] = format("class %s train %d validation %d test %d", name, tr[label], va[label], te[label]) end
    local vm, tm = {}, {}
    for _, attribute in ipairs(self.attributes) do
        local v, t = 0, 0
        for _, row in ipairs(self.validation) do if row.values[attribute.index] == false then v = v + 1 end end
        for _, row in ipairs(self.test) do if row.values[attribute.index] == false then t = t + 1 end end
        vm[#vm + 1], tm[#tm + 1] = v, t
    end
    lines[#lines + 1] = format("missing validation %d test %d", impurity.sum(vm), impurity.sum(tm))
    for index, attribute in ipairs(self.attributes) do lines[#lines + 1] = format("missing %s validation %d test %d", attribute.name, vm[index], tm[index]) end
    return lines
end

function Study:summary_line(name, tree)
    return format("%s nodes %d leaves %d depth %d train %s validation %s test %s", name, #tree:preorder(), #tree:leaves(), tree_depth(tree),
        self:accuracy(tree, self.train), self:accuracy(tree, self.validation), self:accuracy(tree, self.test))
end

function Study:routing_lines()
    local tallies, lines = {}, {"routing pruned test"}
    for _, node in ipairs(self.pruned:internal_nodes()) do tallies[node.number] = {primary = 0, surrogate = 0, default = 0} end
    local complete, incomplete = {}, {}
    for _, row in ipairs(self.test) do
        for _, step in ipairs(self.pruned:route(row).steps) do
            local tally = tallies[step.node.number]
            tally[step.method] = tally[step.method] + 1
        end
        local group = missing_count(row) == 0 and complete or incomplete
        group[#group + 1] = row
    end
    for _, node in ipairs(self.pruned:internal_nodes()) do
        local tally = tallies[node.number]
        lines[#lines + 1] = format("node %d rows %d primary %d surrogate %d default %d", node.number,
            tally.primary + tally.surrogate + tally.default, tally.primary, tally.surrogate, tally.default)
    end
    lines[#lines + 1] = format("complete rows %d correct %s", #complete, self:accuracy(self.pruned, complete))
    lines[#lines + 1] = format("incomplete rows %d correct %s", #incomplete, self:accuracy(self.pruned, incomplete))
    return lines
end

function Study:cross_validation_lines()
    local lines, total = {"cross_validation folds " .. self.settings.folds}, 0
    for fold, tree in ipairs(self.fold_trees) do
        local rows = self:fold_rows(fold)
        local correct = tree:correct_count(rows)
        total = total + correct
        lines[#lines + 1] = format("fold %d rows %d-%d leaves %d correct %s", fold, self.bounds[fold] + 1,
            self.bounds[fold + 1], #tree:leaves(), evaluation.ratio(correct, #rows))
    end
    lines[#lines + 1] = "cv accuracy " .. evaluation.ratio(total, #self.train)
    return lines
end

function Study:depth_lines()
    local lines = {"depth_selection"}
    for _, result in ipairs(self.depth_results) do
        lines[#lines + 1] = format("depth %d leaves %d cv %s train %s validation %s test %s", result.depth,
            #result.tree:leaves(), evaluation.ratio(result.cv, #self.train), self:accuracy(result.tree, self.train),
            self:accuracy(result.tree, self.validation), self:accuracy(result.tree, self.test))
    end
    local selected = self.selected_depth
    lines[#lines + 1] = format("selected depth %d leaves %d test %s", selected.depth, #selected.tree:leaves(), self:accuracy(selected.tree, self.test))
    return lines
end

function Study:cost_complexity_lines()
    local lines = {"cost_complexity"}
    for index, step in ipairs(self.sequence) do
        lines[#lines + 1] = format("subtree %d alpha %s leaves %d train_errors %d validation_errors %d", index - 1,
            evaluation.fraction(step.alpha[1], step.alpha[2] * #self.train, 6), #step.tree:leaves(), training_errors(step.tree), self:validation_errors(step.tree))
    end
    local selected = self.sequence[self.selected_index].tree
    lines[#lines + 1] = format("selected subtree %d leaves %d test %s", self.selected_index - 1, #selected:leaves(), self:accuracy(selected, self.test))
    return lines
end

function Study:model_evaluation(model)
    return evaluation.classification(model .. " test", self.classes, self.test, self.predictions[model])
end

function Study:bagging_lines()
    local lines = {format("bagging trees %d seed %d", self.settings.bag_trees, self.settings.bag_seed)}
    for index, bag in ipairs(self.bags) do
        lines[#lines + 1] = format("bag %d distinct %d leaves %d oob %s", index, bag.distinct, #bag.tree:leaves(), evaluation.ratio(bag.correct, bag.out_of_bag))
    end
    local voted, hits = 0, 0
    for index, votes in ipairs(self.oob_votes) do
        if impurity.sum(votes) > 0 then
            voted = voted + 1
            if impurity.majority(votes) == self.train[index].label then hits = hits + 1 end
        end
    end
    lines[#lines + 1] = format("oob accuracy %s unvoted %d", evaluation.ratio(hits, voted), #self.train - voted)
    append(lines, self:model_evaluation("bagging"))
    return lines
end

function Study:mcnemar_lines()
    local lines = {"mcnemar pruned test"}
    for _, model in ipairs({"grown", "depth", "cost_complexity", "bagging"}) do
        local b, c = 0, 0
        for index, row in ipairs(self.test) do
            local first, second = self.predictions.pruned[index] == row.label, self.predictions[model][index] == row.label
            if first and not second then b = b + 1 end
            if second and not first then c = c + 1 end
        end
        local difference = math.max(0, math.abs(b - c) - 1)
        local squared = difference * difference
        local statistic = b + c == 0 and "0/1 0.0000" or evaluation.fraction(squared, b + c)
        lines[#lines + 1] = format("versus %s b %d c %d statistic %s significant %s", model, b, c, statistic,
            1000 * squared > 3841 * (b + c) and "yes" or "no")
    end
    return lines
end

function Study:auc_lines()
    local lines = {}
    for _, model in ipairs({"grown", "pruned", "bagging"}) do
        local scores = {}
        for index, row in ipairs(self.test) do
            if model == "bagging" then scores[index] = {counts = self.test_votes[index], size = self.settings.bag_trees}
            else
                local leaf = (model == "grown" and self.grown or self.pruned):route(row).leaf
                scores[index] = {counts = leaf.counts, size = leaf.size}
            end
        end
        local parts, total, available = {"auc", model}, 0.0, 0
        for label, name in ipairs(self.classes) do
            local wins, positives, negatives = 0, 0, 0
            for _, row in ipairs(self.test) do
                if row.label == label then positives = positives + 1 else negatives = negatives + 1 end
            end
            for first, row in ipairs(self.test) do
                if row.label == label then
                    for second, other in ipairs(self.test) do
                        if other.label ~= label then
                            local comparison = impurity.compare({scores[first].counts[label], scores[first].size}, {scores[second].counts[label], scores[second].size})
                            if comparison > 0 then wins = wins + 2 elseif comparison == 0 then wins = wins + 1 end
                        end
                    end
                end
            end
            local denominator = 2 * positives * negatives
            parts[#parts + 1], parts[#parts + 2] = name, evaluation.fraction(wins, denominator)
            if denominator > 0 then total, available = total + wins / denominator, available + 1 end
        end
        parts[#parts + 1], parts[#parts + 2] = "macro", available > 0 and evaluation.real(total / available) or "-"
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return lines
end

function Study:learning_curve_lines()
    local lines = {"learning_curve"}
    for _, size in ipairs(self.settings.curve) do
        local grown = evaluation.view(self.builder:grow(slice(self.train, 1, size)))
        local pruned = pruning.reduced_error(grown.root, self.validation)
        lines[#lines + 1] = format("size %d grown leaves %d test %s pruned leaves %d test %s", size, #grown:leaves(),
            self:accuracy(grown, self.test), #pruned:leaves(), self:accuracy(pruned, self.test))
    end
    return lines
end

function Study:evaluation_file()
    return join_sections({self:data_lines(), {self:summary_line("grown", self.grown), self:summary_line("pruned", self.pruned)},
        self:model_evaluation("grown"), self:model_evaluation("pruned"), self:routing_lines(), self:cross_validation_lines(),
        self:depth_lines(), self:cost_complexity_lines(), self:bagging_lines(), self:mcnemar_lines(), self:auc_lines(), self:learning_curve_lines()})
end

function Study:impurity_lines(title, tree)
    local importance, splits, total = {}, {}, 0.0
    for index = 1, #self.attributes do importance[index], splits[index] = 0.0, 0 end
    for _, node in ipairs(tree:internal_nodes()) do
        local index = node.split.attribute.index
        importance[index] = importance[index] + impurity.decrease(node)
        splits[index] = splits[index] + 1
    end
    for _, value in ipairs(importance) do total = total + value end
    local records = {}
    for index, attribute in ipairs(self.attributes) do
        local share = total ~= 0 and importance[index] / total or 0.0
        records[#records + 1] = {index = index, name = attribute.name, share = evaluation.real(share), rounded = tonumber(evaluation.real(share)),
            decrease = evaluation.real(importance[index] / #self.train), splits = splits[index]}
    end
    table.sort(records, function(a, b)
        if a.rounded ~= b.rounded then return a.rounded > b.rounded end
        return a.index < b.index
    end)
    local lines = {"impurity " .. title}
    for rank, record in ipairs(records) do
        lines[#lines + 1] = format("%d %s decrease %s share %s splits %d", rank, record.name, record.decrease, record.share, record.splits)
    end
    return lines
end

function Study:permutation_lines()
    local draw, repeats, size = minstd(self.settings.permutation_seed), self.settings.permutation_repeats, #self.test
    local base, results = self.pruned:correct_count(self.test), {}
    for _, attribute in ipairs(self.attributes) do
        local counts = {}
        for _ = 1, repeats do
            local values, rows = {}, {}
            for index, row in ipairs(self.test) do values[index] = row.values[attribute.index] end
            for position = size, 2, -1 do
                local other = draw() % position + 1
                values[position], values[other] = values[other], values[position]
            end
            for index, row in ipairs(self.test) do
                local changed = copy(row.values)
                changed[attribute.index] = values[index]
                rows[#rows + 1] = {id = row.id, values = changed, label = row.label}
            end
            counts[#counts + 1] = self.pruned:correct_count(rows)
        end
        results[#results + 1] = {attribute = attribute, counts = counts, drop = repeats * base - impurity.sum(counts)}
    end
    table.sort(results, function(a, b)
        if a.drop ~= b.drop then return a.drop > b.drop end
        return a.attribute.index < b.attribute.index
    end)
    local lines = {format("permutation pruned test repeats %d seed %d base %s", repeats, self.settings.permutation_seed, evaluation.ratio(base, size))}
    for rank, result in ipairs(results) do
        lines[#lines + 1] = format("%d %s correct %s drop %s", rank, result.attribute.name, table.concat(result.counts, " "), evaluation.fraction(result.drop, repeats * size))
    end
    return lines
end

function Study:importance_file()
    return join_sections({self:impurity_lines("grown", self.grown), self:impurity_lines("pruned", self.pruned), self:permutation_lines()})
end

local function main()
    local study = Study.new(dataset.load("input"))
    assert(os.execute('mkdir -p "output"'))
    local files = {{"tree.txt", study:tree_file()}, {"pruned_tree.txt", study:pruned_tree_file()},
        {"predictions.csv", study:predictions_file()}, {"rules.txt", study:rules_file()},
        {"evaluation.txt", study:evaluation_file()}, {"importance.txt", study:importance_file()}}
    for _, entry in ipairs(files) do
        local file = assert(io.open("output/" .. entry[1], "w"))
        file:write(table.concat(entry[2], "\n"), "\n")
        file:close()
    end
end

main()
