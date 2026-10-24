"""One-step expected-count and observed-count HMM estimation."""

from inference import forward_backward, posterior_transition, scaled_forward
from model_io import Model


def smoothed_model(template, name, initial, transition, emission, alpha):
    return Model(
        name, template.states, template.symbols, template.missing,
        [value + alpha for value in initial],
        [[value + alpha for value in row] for row in transition],
        [[value + alpha for value in row] for row in emission],
    )


def baum_welch_step(model, sequences, pseudocount):
    count = len(model.states)
    initial = [0.0] * count
    transition = [[0.0] * count for _ in range(count)]
    emission = [[0.0] * len(model.symbols) for _ in range(count)]
    for observations in sequences:
        result = forward_backward(model, observations)
        for state in range(count):
            initial[state] += result.posterior[0][state]
        for position, observation in enumerate(observations):
            for state in range(count):
                if observation != -1:
                    emission[state][observation] += result.posterior[position][state]
                if position + 1 < len(observations):
                    for following in range(count):
                        transition[state][following] += posterior_transition(
                            model, result, position, state, following
                        )
    return smoothed_model(
        model, "BAUM_WELCH", initial, transition, emission, pseudocount
    )


def estimate_by_counting(template, pairs, alpha, name="SUPERVISED"):
    count = len(template.states)
    initial = [0] * count
    transition = [[0] * count for _ in range(count)]
    emission = [[0] * len(template.symbols) for _ in range(count)]
    for observations, path in pairs:
        initial[path[0]] += 1
        for position, state in enumerate(path):
            observation = observations[position]
            if observation != -1:
                emission[state][observation] += 1
            if position + 1 < len(path):
                transition[state][path[position + 1]] += 1
    return smoothed_model(template, name, initial, transition, emission, alpha)


def total_loglik(model, sequences):
    total = 0.0
    for observations in sequences:
        total += scaled_forward(model, observations).loglik
    return total
