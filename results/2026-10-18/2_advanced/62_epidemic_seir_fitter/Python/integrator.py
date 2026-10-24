def rk4_step(rates, state, multiplier):
    h = 0.25
    half = h / 2.0
    sixth = h / 6.0
    k1 = rates(state, multiplier)
    k2 = rates([a + half * p for a, p in zip(state, k1)], multiplier)
    k3 = rates([a + half * q for a, q in zip(state, k2)], multiplier)
    k4 = rates([a + h * r for a, r in zip(state, k3)], multiplier)
    return [a + sixth * (((p + 2.0 * q) + 2.0 * r) + s)
            for a, p, q, r, s in zip(state, k1, k2, k3, k4)]


def simulate(rates, initial, multipliers, inflows):
    state = list(initial)
    daily = []
    for multiplier in multipliers:
        for index in inflows:
            state[index] = 0.0
        for _ in range(4):
            state = rk4_step(rates, state, multiplier)
        daily.append(tuple(state))
    return daily
