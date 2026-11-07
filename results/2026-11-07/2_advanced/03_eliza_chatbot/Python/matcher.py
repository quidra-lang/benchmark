def is_wildcard(element):
    return element in ("*", "#") or element.startswith("@")


def word_fits(element, word, group_words):
    if element == "#":
        return True
    if element.startswith("@"):
        return word in group_words.get(element[1:], ())
    return element == word


def match_from(pattern, words, group_words, position, start, ends):
    if position == len(pattern):
        return start == len(words)
    if pattern[position] == "*":
        candidates = range(start, len(words) + 1)
    elif start < len(words) and word_fits(pattern[position], words[start], group_words):
        candidates = [start + 1]
    else:
        return False
    for end in candidates:
        ends.append(end)
        if match_from(pattern, words, group_words, position + 1, end, ends):
            return True
        ends.pop()
    return False


def match_pattern(pattern, words, group_words):
    ends = []
    if not match_from(pattern, words, group_words, 0, 0, ends):
        return None
    bindings = []
    start = 0
    for element, end in zip(pattern, ends):
        if is_wildcard(element):
            bindings.append(words[start:end])
        start = end
    return bindings


def element_covers(element, other, group_words):
    if element == "#":
        return other != "*"
    if element.startswith("@"):
        members = group_words[element[1:]]
        if other.startswith("@"):
            return all(word in members for word in group_words[other[1:]])
        return other in members
    return element == other


def covers_from(earlier, later, group_words, position, start):
    if position == len(earlier):
        return start == len(later)
    if earlier[position] == "*":
        return any(
            covers_from(earlier, later, group_words, position + 1, end)
            for end in range(start, len(later) + 1)
        )
    if start < len(later) and element_covers(earlier[position], later[start], group_words):
        return covers_from(earlier, later, group_words, position + 1, start + 1)
    return False


def pattern_covers(earlier, later, group_words):
    return covers_from(earlier, later, group_words, 0, 0)
