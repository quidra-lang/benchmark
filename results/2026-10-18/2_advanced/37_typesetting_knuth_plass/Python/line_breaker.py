"""Integer line costs and deterministic optimal and greedy breakings."""


def line_class(slack, last):
    if last:
        return 1
    if slack <= 1:
        return 0
    if slack <= 3:
        return 1
    if slack <= 6:
        return 2
    return 3


def line_cost(metrics, start, end, previous_class, params):
    slack = metrics.slack(start, end)
    last = end == metrics.end
    current_class = line_class(slack, last)
    cost = params["line_penalty"]
    if slack < 0:
        cost += params["overfull_penalty"]
    elif not last:
        cost += slack * slack
    if metrics.breaks[end].midword:
        cost += params["hyphen_penalty"]
        if metrics.breaks[start].midword:
            cost += params["double_hyphen_demerit"]
    if last and metrics.breaks[start].midword:
        cost += params["final_hyphen_demerit"]
    if abs(current_class - previous_class) >= 2:
        cost += params["fitness_demerit"]
    return cost


def breaking_cost(metrics, breaking, params):
    total = 0
    previous = 0
    previous_class = 1
    for end in breaking:
        total += line_cost(metrics, previous, end, previous_class, params)
        previous_class = line_class(metrics.slack(previous, end),
                                    end == metrics.end)
        previous = end
    return total


def knuth_plass(metrics, params):
    states = [{} for _ in range(metrics.end + 1)]
    states[0][1] = (0, None, None)
    for end in range(1, metrics.end + 1):
        for start in range(end - 1, -1, -1):
            slack = metrics.slack(start, end)
            if slack < 0 and end != start + 1:
                # Earlier starts only lengthen a line; C1 never exceeds C2.
                break
            current_class = line_class(slack, end == metrics.end)
            for previous_class, previous in states[start].items():
                cost = previous[0] + line_cost(
                    metrics, start, end, previous_class, params
                )
                candidate = (cost, start, previous_class)
                best = states[end].get(current_class)
                if best is None or candidate < best:
                    states[end][current_class] = candidate

    breaking = []
    position = metrics.end
    current_class = 1
    cost = states[position][current_class][0]
    while position:
        breaking.append(position)
        _, position, current_class = states[position][current_class]
    breaking.reverse()
    return breaking, cost


def greedy(metrics, params):
    breaking = []
    start = 0
    while start < metrics.end:
        chosen = start + 1
        if metrics.slack(start, chosen) >= 0:
            for end in range(chosen + 1, metrics.end + 1):
                if metrics.slack(start, end) < 0:
                    break
                chosen = end
        breaking.append(chosen)
        start = chosen
    return breaking, breaking_cost(metrics, breaking, params)


def break_text(metrics, method, params):
    if method == "kp":
        return knuth_plass(metrics, params)
    return greedy(metrics, params)
