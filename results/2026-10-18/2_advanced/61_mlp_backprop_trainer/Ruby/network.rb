require_relative 'layers'

class Network
  attr_reader :name, :width, :height, :classes, :layers, :is_weight, :parameters, :weight_indices

  def initialize(definition)
    @name, @width, @height = definition.values_at(:name, :width, :height)
    previous, index = @width * @height, 0
    @is_weight = []
    @layers = definition[:layers].map do |layer|
      units = layer[:units]
      count = units * previous
      result = layer.merge(inputs: previous, outputs: units, weight_start: index, weight_end: index + count,
                           bias_start: index + count, bias_end: index + count + units)
      @is_weight.concat(Array.new(count, true) + Array.new(units, false))
      index += count + units
      previous = units
      result
    end
    @parameters, @classes = index, previous
    @weight_indices = @is_weight.each_index.select { |i| @is_weight[i] }
  end

  def layer_values(theta, layer)
    [theta[layer[:weight_start]...layer[:weight_end]].each_slice(layer[:inputs]).to_a,
     theta[layer[:bias_start]...layer[:bias_end]]]
  end

  def forward(theta, image)
    a, z, weights = [image.vector], [], []
    scores = loss = errors = nil
    @layers.each_with_index do |layer, i|
      w, biases = layer_values(theta, layer)
      weights << w
      pre = Layers.preactivation(w, biases, a[-1])
      z << pre
      if i == @layers.size - 1
        scores, loss, errors = Layers.output(layer[:activation], pre, image.label)
        a << scores
      else
        a << pre.map { |v| Layers.activate(layer[:activation], v) }
      end
    end
    { a: a, z: z, weights: weights, scores: scores, loss: loss, output_delta: errors }
  end

  def gradient(theta, image, input_gradient: false)
    cache = forward(theta, image)
    deltas = Array.new(@layers.size)
    deltas[-1] = cache[:output_delta]
    (@layers.size - 2).downto(0) do |i|
      propagated = Layers.backward_sum(cache[:weights][i + 1], deltas[i + 1])
      deltas[i] = propagated.each_with_index.map do |v, j|
        v * Layers.derivative(@layers[i][:activation], cache[:z][i][j], cache[:a][i + 1][j])
      end
    end
    grad = Array.new(@parameters, 0.0)
    @layers.each_with_index do |layer, l|
      destination = layer[:weight_start]
      layer[:outputs].times do |j|
        layer[:inputs].times do |i|
          grad[destination] = deltas[l][j] * cache[:a][l][i]
          destination += 1
        end
        grad[layer[:bias_start] + j] = deltas[l][j]
      end
    end
    input_gradient ? [grad, cache, Layers.backward_sum(cache[:weights][0], deltas[0])] : [grad, cache]
  end
end
