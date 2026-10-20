class Optimizer
  def initialize(run, count)
    @run = run
    @velocity, @first, @second = Array.new(count, 0.0), Array.new(count, 0.0), Array.new(count, 0.0)
    @power1 = @power2 = 1.0
  end

  def epoch_rate(epoch, step, gamma)
    rate = @run[:rate]
    ((epoch - 1) / step).times { rate *= gamma }
    rate
  end

  def update(theta, grad, rate)
    kind = @run[:optimizer]
    beta1, beta2, epsilon = @run[:extra] if kind == 'ADAM'
    if kind == 'ADAM'
      @power1 *= beta1
      @power2 *= beta2
    end
    grad.each_with_index do |g, i|
      case kind
      when 'SGD' then theta[i] -= rate * g
      when 'MOMENTUM'
        @velocity[i] = @run[:extra][0] * @velocity[i] + g
        theta[i] -= rate * @velocity[i]
      when 'ADAM'
        @first[i] = beta1 * @first[i] + (1 - beta1) * g
        @second[i] = beta2 * @second[i] + (1 - beta2) * g * g
        first, second = @first[i] / (1 - @power1), @second[i] / (1 - @power2)
        theta[i] -= rate * first / (Math.sqrt(second) + epsilon)
      end
    end
  end
end
