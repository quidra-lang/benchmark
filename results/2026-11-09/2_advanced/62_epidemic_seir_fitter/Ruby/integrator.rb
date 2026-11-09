module Integrator
  def self.rk4_step(rates, state, multiplier)
    h = 0.25
    half, sixth = h / 2.0, h / 6.0
    k1 = rates.call(state, multiplier)
    k2 = rates.call(state.each_index.map { |i| state[i] + half * k1[i] }, multiplier)
    k3 = rates.call(state.each_index.map { |i| state[i] + half * k2[i] }, multiplier)
    k4 = rates.call(state.each_index.map { |i| state[i] + h * k3[i] }, multiplier)
    state.each_index.map { |i| state[i] + sixth * (((k1[i] + 2.0 * k2[i]) + 2.0 * k3[i]) + k4[i]) }
  end

  def self.simulate(rates, initial, multipliers, inflows)
    state = initial.dup
    multipliers.map do |multiplier|
      inflows.each { |i| state[i] = 0.0 }
      4.times { state = rk4_step(rates, state, multiplier) }
      state.dup
    end
  end
end
