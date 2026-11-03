"""Scaled HMM inference with state-order tie breaking."""

from collections import namedtuple
from math import log


Forward = namedtuple("Forward", "values scales emissions loglik")
ForwardBackward = namedtuple(
    "ForwardBackward", "forward backward scales emissions posterior loglik"
)
Decoding = namedtuple(
    "Decoding", "viterbi viterbi_logprob posterior confidence fb"
)


def maximum_index(values):
    best = 0
    for index in range(1, len(values)):
        if values[index] > values[best]:
            best = index
    return best


def emission_factors(model, observation):
    if observation == -1:
        return [1.0] * len(model.states)
    return [row[observation] for row in model.emission]


def log_emission_factors(model, observation):
    if observation == -1:
        return [0.0] * len(model.states)
    return [log(row[observation]) for row in model.emission]


def scaled_forward(model, observations):
    count = len(model.states)
    emissions = [emission_factors(model, symbol) for symbol in observations]
    values = []
    scales = []
    loglik = 0.0
    for position, factors in enumerate(emissions):
        unscaled = []
        for state in range(count):
            if position == 0:
                value = model.initial[state] * factors[state]
            else:
                total = 0.0
                for previous in range(count):
                    total += values[position - 1][previous] * model.transition[previous][state]
                value = total * factors[state]
            unscaled.append(value)
        scale = 0.0
        for value in unscaled:
            scale += value
        scales.append(scale)
        values.append([value / scale for value in unscaled])
        loglik += log(scale)
    return Forward(values, scales, emissions, loglik)


def forward_backward(model, observations):
    forward = scaled_forward(model, observations)
    count = len(model.states)
    length = len(observations)
    backward = [[0.0] * count for _ in observations]
    backward[-1] = [1.0] * count
    for position in range(length - 2, -1, -1):
        for state in range(count):
            total = 0.0
            for following in range(count):
                total += (
                    model.transition[state][following]
                    * forward.emissions[position + 1][following]
                    * backward[position + 1][following]
                )
            backward[position][state] = total / forward.scales[position + 1]
    posterior = [
        [forward.values[t][state] * backward[t][state] for state in range(count)]
        for t in range(length)
    ]
    return ForwardBackward(
        forward.values, backward, forward.scales, forward.emissions,
        posterior, forward.loglik,
    )


def posterior_transition(model, result, position, state, following):
    return (
        result.forward[position][state]
        * model.transition[state][following]
        * result.emissions[position + 1][following]
        * result.backward[position + 1][following]
        / result.scales[position + 1]
    )


def viterbi(model, observations):
    count = len(model.states)
    transitions = [[log(value) for value in row] for row in model.transition]
    factors = log_emission_factors(model, observations[0])
    scores = [log(model.initial[state]) + factors[state] for state in range(count)]
    predecessors = [[0] * count]
    for observation in observations[1:]:
        factors = log_emission_factors(model, observation)
        next_scores = []
        previous_states = []
        for state in range(count):
            candidates = [
                scores[previous] + transitions[previous][state]
                for previous in range(count)
            ]
            previous = maximum_index(candidates)
            previous_states.append(previous)
            next_scores.append(candidates[previous] + factors[state])
        predecessors.append(previous_states)
        scores = next_scores
    path = [0] * len(observations)
    path[-1] = maximum_index(scores)
    logprob = scores[path[-1]]
    for position in range(len(observations) - 1, 0, -1):
        path[position - 1] = predecessors[position][path[position]]
    return path, logprob


def decode(model, observations):
    fb = forward_backward(model, observations)
    path, logprob = viterbi(model, observations)
    posterior = [maximum_index(row) for row in fb.posterior]
    confidence = [row[state] for row, state in zip(fb.posterior, posterior)]
    return Decoding(path, logprob, posterior, confidence, fb)
