local S = {}
S.__index = S
function S:nonbound(i) return self.alpha[i] > 0 and self.alpha[i] < self.C end
function S:snap(value)
    if value < 0.00000001 then return 0.0 end
    if value > self.C - 0.00000001 then return self.C end
    return value
end
function S:take(first, second)
    if first == second then return false end
    local alpha1, alpha2, y1, y2, e1, e2 = self.alpha[first], self.alpha[second], self.labels[first], self.labels[second], self.errors[first], self.errors[second]
    local lower, upper
    if y1 ~= y2 then lower, upper = math.max(0.0, alpha2 - alpha1), math.min(self.C, self.C + alpha2 - alpha1)
    else lower, upper = math.max(0.0, alpha2 + alpha1 - self.C), math.min(self.C, alpha2 + alpha1) end
    if lower == upper then return false end
    local k11, k12, k22 = self.matrix[first][first], self.matrix[first][second], self.matrix[second][second]
    local eta = k11 + k22 - 2 * k12
    if eta <= 0 then return false end
    local a2, clipping = alpha2 + y2 * (e1 - e2) / eta, "none"
    if a2 < lower then a2, clipping = lower, "lower" elseif a2 > upper then a2, clipping = upper, "upper" end
    a2 = self:snap(a2)
    if math.abs(a2 - alpha2) < self.eps * (a2 + alpha2 + self.eps) then return false end
    local a1 = self:snap(alpha1 + y1 * y2 * (alpha2 - a2))
    local t1, t2 = y1 * (a1 - alpha1), y2 * (a2 - alpha2)
    local b1, b2 = e1 + t1 * k11 + t2 * k12 + self.b, e2 + t1 * k12 + t2 * k22 + self.b
    local threshold
    if a1 > 0 and a1 < self.C then threshold = b1 elseif a2 > 0 and a2 < self.C then threshold = b2 else threshold = (b1 + b2) / 2 end
    local delta = threshold - self.b
    for i = 1, #self.points do self.errors[i] = self.errors[i] + (t1 * self.matrix[first][i] + t2 * self.matrix[second][i] - delta) end
    if a1 > 0 and a1 < self.C then self.errors[first] = 0.0 end
    if a2 > 0 and a2 < self.C then self.errors[second] = 0.0 end
    self.alpha[first], self.alpha[second], self.b = a1, a2, threshold
    self.steps, self.clipping[clipping] = self.steps + 1, self.clipping[clipping] + 1
    return true
end
function S:examine(second)
    self.examined = self.examined + 1
    local residual = self.errors[second] * self.labels[second]
    if not (residual < -self.tolerance and self.alpha[second] < self.C or residual > self.tolerance and self.alpha[second] > 0) then return 0 end
    local partner, largest = nil, -1.0
    for i = 1, #self.points do
        if i ~= second and self:nonbound(i) then
            local difference = math.abs(self.errors[i] - self.errors[second])
            if difference > largest then partner, largest = i, difference end
        end
    end
    if partner and self:take(partner, second) then self.choices.heuristic = self.choices.heuristic + 1; return 1 end
    for i = 1, #self.points do if self:nonbound(i) and self:take(i, second) then self.choices.nonbound_loop = self.choices.nonbound_loop + 1; return 1 end end
    for i = 1, #self.points do if self:take(i, second) then self.choices.full_loop = self.choices.full_loop + 1; return 1 end end
    return 0
end
function S:decision(point)
    local total = 0.0
    for i, alpha in ipairs(self.alpha) do if alpha > 0 then total = total + alpha * self.labels[i] * self.kernel:value(self.points[i], point) end end
    return total - self.b
end
function S:training_decisions()
    local values = {}
    for i, row in ipairs(self.matrix) do
        local total = 0.0
        for j, alpha in ipairs(self.alpha) do if alpha > 0 then total = total + alpha * self.labels[j] * row[j] end end
        values[i] = total - self.b
    end
    return values
end
function S.train(points, labels, kernel, matrix, coefficient, settings)
    local model = setmetatable({ points = points, labels = labels, kernel = kernel, matrix = matrix, C = coefficient, tolerance = settings.tolerance,
        eps = settings.eps, max_passes = settings.max_passes, alpha = {}, errors = {}, b = 0.0, full_passes = 0, nonbound_passes = 0, passes = 0,
        examined = 0, steps = 0, choices = { heuristic = 0, nonbound_loop = 0, full_loop = 0 }, clipping = { none = 0, lower = 0, upper = 0 }, records = {}, converged = false }, S)
    for i, label in ipairs(labels) do model.alpha[i], model.errors[i] = 0.0, -label + 0.0 end
    local all = true
    while true do
        local examined, changed = model.examined, 0
        for i = 1, #points do if all or model:nonbound(i) then changed = changed + model:examine(i) end end
        if all then model.full_passes = model.full_passes + 1 else model.nonbound_passes = model.nonbound_passes + 1 end
        model.passes = model.passes + 1
        local record = { full = all, examined = model.examined - examined, changed = changed }
        if all then record.alpha = {}; for i, value in ipairs(model.alpha) do record.alpha[i] = value end end
        model.records[#model.records + 1] = record
        if all and changed == 0 then model.converged = true; break end
        if model.passes == model.max_passes then break end
        if all then all = false elseif changed == 0 then all = true end
    end
    return model
end
return S
