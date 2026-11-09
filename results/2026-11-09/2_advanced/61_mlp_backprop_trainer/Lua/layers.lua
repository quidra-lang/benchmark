local L = {}
function L.activation(kind, value)
    if kind == "TANH" then return 1 - 2 / (math.exp(2 * value) + 1) end
    if kind == "SIGMOID" then return 1 / (1 + math.exp(-value)) end
    return value > 0 and value or 0.0
end
function L.derivative(kind, z, activation)
    if kind == "TANH" then return 1 - activation * activation end
    if kind == "SIGMOID" then return activation * (1 - activation) end
    return z > 0 and 1.0 or 0.0
end
function L.pre_activation(theta, layer, activation)
    local result, position = {}, layer.weight_start
    for j = 1, layer.outputs do
        local sum = 0.0
        for i = 1, layer.inputs do sum, position = sum + theta[position] * activation[i], position + 1 end
        result[j] = sum + theta[layer.bias_start + j - 1]
    end
    return result
end
function L.backward(theta, layer, errors)
    local result = {}
    for i = 1, layer.inputs do
        local sum = 0.0
        for j = 1, layer.outputs do sum = sum + theta[layer.weight_start + (j - 1) * layer.inputs + i - 1] * errors[j] end
        result[i] = sum
    end
    return result
end
function L.output(kind, z, label)
    local scores, errors, loss = {}, {}, 0.0
    if kind == "SOFTMAX" then
        local maximum, total = math.max(table.unpack(z)), 0.0
        for i, value in ipairs(z) do scores[i] = math.exp(value - maximum); total = total + scores[i] end
        for i = 1, #z do scores[i] = scores[i] / total; errors[i] = scores[i] - (i - 1 == label and 1.0 or 0.0) end
        loss = math.log(total) - (z[label + 1] - maximum)
    else
        for i, value in ipairs(z) do
            local score = 1 / (1 + math.exp(-value))
            local residual = score - (i - 1 == label and 1.0 or 0.0)
            scores[i], errors[i] = score, 2 * residual * score * (1 - score) / #z
            loss = loss + residual * residual
        end
        loss = loss / #z
    end
    return scores, loss, errors
end
return L
