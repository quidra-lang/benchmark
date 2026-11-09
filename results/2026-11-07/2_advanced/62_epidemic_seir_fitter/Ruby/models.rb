module Models
  def self.seird(population, sigma, fatality, beta, gamma)
    lambda do |state, multiplier|
      s, e, i = state
      flow = beta * multiplier * s * i / population
      progression = sigma * e
      removal = gamma * i
      [-flow, flow - progression, progression - removal,
       (1.0 - fatality) * gamma * i, fatality * gamma * i, progression]
    end
  end

  def self.sir(population, beta, gamma)
    lambda do |state, multiplier|
      s, i = state
      flow = beta * multiplier * s * i / population
      removal = gamma * i
      [-flow, flow - removal, removal, flow]
    end
  end

  def self.age_seird(populations, fatalities, sigma, beta, gamma, contacts)
    lambda do |state, multiplier|
      populations.each_index.flat_map do |g|
        s, e, i = state[6 * g, 3]
        pressure = 0.0
        populations.each_index { |h| pressure += contacts[g][h] * state[6 * h + 2] / populations[h] }
        force = beta * multiplier * pressure
        flow = force * s
        progression = sigma * e
        removal = gamma * i
        [-flow, flow - progression, progression - removal,
         (1.0 - fatalities[g]) * gamma * i, fatalities[g] * gamma * i, progression]
      end
    end
  end

  def self.generation(sigma, gamma)
    lambda do |state, _multiplier|
      e, i = state
      progression = sigma * e
      removal = gamma * i
      [-progression, progression - removal, removal]
    end
  end
end
