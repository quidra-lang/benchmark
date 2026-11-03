local L = require("layers")
local E = require("evaluation")
local N = {}
function N.zeros(count) local result = {}; for i = 1, count do result[i] = 0.0 end; return result end
function N.copy(values) local result = {}; for i, value in ipairs(values) do result[i] = value end; return result end
function N.layout(architecture)
    local result, previous, position = { layers = {}, is_weight = {}, parameters = 0, weight_count = 0 }, architecture.width * architecture.height, 1
    for _, definition in ipairs(architecture.layers) do
        local outputs, weights = definition.units, definition.units * previous
        local layer = { inputs = previous, outputs = outputs, activation = definition.activation, kind = definition.kind,
            weight_start = position, weight_finish = position + weights - 1, bias_start = position + weights, bias_finish = position + weights + outputs - 1 }
        result.layers[#result.layers + 1] = layer
        for _ = 1, weights do result.is_weight[#result.is_weight + 1] = true end
        for _ = 1, outputs do result.is_weight[#result.is_weight + 1] = false end
        result.weight_count, position, previous = result.weight_count + weights, layer.bias_finish + 1, outputs
    end
    result.parameters = position - 1
    return result
end
function N.forward(layout, theta, image)
    local cache = { a = { [0] = image.vector }, z = {} }
    for i, layer in ipairs(layout.layers) do
        local z = L.pre_activation(theta, layer, cache.a[i - 1])
        cache.z[i] = z
        if i == #layout.layers then cache.scores, cache.loss, cache.output_delta = L.output(layer.activation, z, image.label); cache.a[i] = cache.scores
        else
            local activations = {}
            for j, value in ipairs(z) do activations[j] = L.activation(layer.activation, value) end
            cache.a[i] = activations
        end
    end
    return cache
end
function N.gradient(layout, theta, image, input_gradient)
    local cache, deltas = N.forward(layout, theta, image), {}
    local layers = layout.layers
    deltas[#layers] = cache.output_delta
    for i = #layers - 1, 1, -1 do
        local propagated, layer = L.backward(theta, layers[i + 1], deltas[i + 1]), layers[i]
        deltas[i] = {}
        for j, value in ipairs(propagated) do deltas[i][j] = value * L.derivative(layer.activation, cache.z[i][j], cache.a[i][j]) end
    end
    local grad = N.zeros(layout.parameters)
    for i, layer in ipairs(layers) do
        local position = layer.weight_start
        for j = 1, layer.outputs do
            for k = 1, layer.inputs do grad[position], position = deltas[i][j] * cache.a[i - 1][k], position + 1 end
            grad[layer.bias_start + j - 1] = deltas[i][j]
        end
    end
    if input_gradient then return grad, cache, L.backward(theta, layers[1], deltas[1]) end
    return grad, cache
end
function N.average_gradient(layout, theta, images)
    local result, loss = N.zeros(layout.parameters), 0.0
    for _, image in ipairs(images) do
        local grad, cache = N.gradient(layout, theta, image)
        loss = loss + cache.loss
        for i, value in ipairs(grad) do result[i] = result[i] + value end
    end
    for i = 1, #result do result[i] = result[i] / #images end
    return result, loss / #images
end
function N.evaluate(layout, theta, images)
    local result, total = { outcomes = {}, correct = 0 }, 0.0
    for _, image in ipairs(images) do
        local cache = N.forward(layout, theta, image)
        local prediction = E.best_two(cache.scores)
        local hidden = {}
        for i = 1, #layout.layers - 1 do hidden[i] = cache.a[i] end
        result.outcomes[#result.outcomes + 1] = { id = image.id, label = image.label, predicted = prediction, confidence = cache.scores[prediction + 1], scores = cache.scores, loss = cache.loss, hidden = hidden }
        total = total + cache.loss
        if prediction == image.label then result.correct = result.correct + 1 end
    end
    result.loss = total / #images
    return result
end
return N
