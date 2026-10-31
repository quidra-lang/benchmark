def seird(population, sigma, fatality, beta, gamma):
    def rates(state, multiplier):
        susceptible, exposed, infectious, _, _, _ = state
        flow = beta * multiplier * susceptible * infectious / population
        progression = sigma * exposed
        removal = gamma * infectious
        return (-flow, flow - progression, progression - removal,
                (1.0 - fatality) * gamma * infectious,
                fatality * gamma * infectious, progression)
    return rates


def sir(population, beta, gamma):
    def rates(state, multiplier):
        susceptible, infectious, _, _ = state
        flow = beta * multiplier * susceptible * infectious / population
        removal = gamma * infectious
        return -flow, flow - removal, removal, flow
    return rates


def age_seird(populations, fatalities, sigma, beta, gamma, contacts):
    def rates(state, multiplier):
        result = []
        for group, population in enumerate(populations):
            start = 6 * group
            susceptible, exposed, infectious = state[start:start + 3]
            pressure = 0.0
            for other, other_population in enumerate(populations):
                pressure += contacts[group][other] * state[6 * other + 2] / other_population
            force = beta * multiplier * pressure
            flow = force * susceptible
            progression = sigma * exposed
            removal = gamma * infectious
            result.extend((-flow, flow - progression, progression - removal,
                           (1.0 - fatalities[group]) * gamma * infectious,
                           fatalities[group] * gamma * infectious, progression))
        return result
    return rates


def generation(sigma, gamma):
    def rates(state, multiplier):
        exposed, infectious, _ = state
        progression = sigma * exposed
        removal = gamma * infectious
        return -progression, progression - removal, removal
    return rates
