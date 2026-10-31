"""Breslow likelihood evaluation and exactly 25 Newton-Raphson steps."""

from itertools import groupby
from math import exp, log

from numerics import solve, total


def evaluate(subjects, vectors, beta):
    size = len(beta)
    predictors = [total(coefficient * value for coefficient, value in zip(beta, x))
                  for x in vectors]
    relative_risks = [exp(value) for value in predictors]
    order = sorted(range(len(subjects)),
                   key=lambda index: (-subjects[index]["time"], subjects[index]["id"]))
    s0 = 0.0
    s1 = [0.0] * size
    s2 = [[0.0] * size for _ in range(size)]
    likelihood = 0.0
    score = [0.0] * size
    information = [[0.0] * size for _ in range(size)]
    event_sums = {}
    for time, indices in groupby(order, key=lambda index: subjects[index]["time"]):
        at_time = list(indices)
        for index in at_time:
            risk = relative_risks[index]
            x = vectors[index]
            s0 += risk
            for c in range(size):
                s1[c] += risk * x[c]
                for d in range(size):
                    s2[c][d] += risk * x[c] * x[d]
        events = [index for index in at_time if subjects[index]["event"]]
        if not events:
            continue
        count = len(events)
        likelihood += total(predictors[index] for index in events) - count * log(s0)
        for c in range(size):
            score[c] += sum(vectors[index][c] for index in events) - count * s1[c] / s0
            for d in range(size):
                information[c][d] += count * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0))
        event_sums[time] = {"s0": s0, "s1": s1[:], "events": count}
    return {
        "loglik": likelihood,
        "score": score,
        "information": information,
        "predictors": predictors,
        "event_sums": event_sums,
    }


def fit(subjects, vectors):
    beta = [0.0] * len(vectors[0])
    null = evaluate(subjects, vectors, beta)
    current = null
    iterations = []
    for iteration in range(1, 26):
        change = solve(current["information"], current["score"])
        beta = [value + step for value, step in zip(beta, change)]
        iterations.append((iteration, current["loglik"], beta[:]))
        current = evaluate(subjects, vectors, beta)
    return {"beta": beta, "null": null, "final": current, "iterations": iterations}
