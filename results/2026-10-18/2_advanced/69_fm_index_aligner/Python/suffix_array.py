"""Stable radix prefix doubling under the task's six-symbol order."""


SYMBOLS = "$#ACGT"
SYMBOL_NUMBER = {symbol: number for number, symbol in enumerate(SYMBOLS)}
BASES = "ACGT"


def counting_sort(positions, keys, key_count):
    counts = [0] * key_count
    for position in positions:
        counts[keys[position]] += 1
    offset = 0
    for key, count in enumerate(counts):
        counts[key] = offset
        offset += count
    result = [0] * len(positions)
    for position in positions:
        key = keys[position]
        result[counts[key]] = position
        counts[key] += 1
    return result


def build(text):
    size = len(text)
    codes = [SYMBOL_NUMBER[symbol] for symbol in text]
    order = counting_sort(range(size), codes, len(SYMBOLS))
    ranks = [0] * size
    count, previous = 0, None
    for position in order:
        if codes[position] != previous:
            count += 1
            previous = codes[position]
        ranks[position] = count - 1
    classes, width = [count], 1
    while count < size:
        second = [ranks[position + width] + 1 if position + width < size else 0
                  for position in range(size)]
        order = counting_sort(range(size), second, count + 1)
        order = counting_sort(order, ranks, count)
        updated = [0] * size
        count, previous = 0, None
        for position in order:
            key = ranks[position], second[position]
            if key != previous:
                count += 1
                previous = key
            updated[position] = count - 1
        ranks = updated
        classes.append(count)
        width *= 2
    return order, classes


def direct_sort(text):
    return sorted(range(len(text)), key=lambda position: text[position:])


def adjacent_check(text, suffixes):
    ordered = lcp_sum = 0
    longest, longest_row = -1, 1
    for row in range(1, len(suffixes)):
        left, right = suffixes[row - 1], suffixes[row]
        common = 0
        while text[left + common] == text[right + common]:
            common += 1
        ordered += SYMBOL_NUMBER[text[left + common]] < SYMBOL_NUMBER[text[right + common]]
        lcp_sum += common
        if common > longest:
            longest, longest_row = common, row
    return ordered, lcp_sum, longest, longest_row
