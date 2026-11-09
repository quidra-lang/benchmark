from math import gcd


class Confusion:
    def __init__(self, predictions, targets):
        self.tp = 0
        self.fp = 0
        self.tn = 0
        self.fn = 0
        for prediction, target in zip(predictions, targets):
            if prediction == 1 and target == 1:
                self.tp += 1
            elif prediction == 1:
                self.fp += 1
            elif target == 0:
                self.tn += 1
            else:
                self.fn += 1


class RocPoint:
    def __init__(self, threshold, tp, fp):
        self.threshold = threshold
        self.tp = tp
        self.fp = fp


def fixed(value, places):
    text = f"{value:.{places}f}"
    if text.startswith("-") and float(text) == 0:
        return text[1:]
    return text


def ratio(numerator, denominator):
    if denominator == 0:
        return "-"
    rounded = (20000 * numerator + denominator) // (2 * denominator)
    return f"{rounded // 10000}.{rounded % 10000:04d}"


def fraction(numerator, denominator):
    divisor = gcd(numerator, denominator)
    reduced = f"{numerator // divisor}/{denominator // divisor}"
    return f"{reduced} {ratio(numerator, denominator)}"


def auc(scores, targets):
    order = sorted(range(len(scores)), key=lambda i: scores[i])
    positives = sum(targets)
    negatives = len(targets) - positives
    rank_sum = 0
    start = 0
    while start < len(order):
        end = start
        while end + 1 < len(order) and scores[order[end + 1]] == scores[order[start]]:
            end += 1
        for position in range(start, end + 1):
            if targets[order[position]] == 1:
                rank_sum += start + end + 2
        start = end + 1
    return rank_sum - positives * (positives + 1), 2 * positives * negatives


def roc_points(probabilities, targets):
    order = sorted(range(len(probabilities)), key=lambda j: -probabilities[j])
    points = []
    tp = 0
    fp = 0
    for position, j in enumerate(order):
        if targets[j] == 1:
            tp += 1
        else:
            fp += 1
        last = position + 1 == len(order)
        if last or probabilities[order[position + 1]] != probabilities[j]:
            points.append(RocPoint(probabilities[j], tp, fp))
    return points
