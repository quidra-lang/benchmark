from script_loader import is_reference


LINE_WIDTH = 72
FIRST_PREFIX = "ELIZA: "
CONTINUATION_PREFIX = " " * 7


def reflect(words, reflections):
    reflected = []
    for word in words:
        reflected.extend(reflections.get(word, [word]))
    return reflected


def binding(bindings, number):
    if 1 <= number <= len(bindings):
        return bindings[number - 1]
    return []


def build_reply(template, bindings, reflections):
    pieces = []
    index = 0
    while index < len(template):
        chunk = template[index:index + 3]
        if is_reference(chunk):
            pieces.append(" ".join(reflect(binding(bindings, int(chunk[1])), reflections)))
            index += 3
        else:
            pieces.append(template[index])
            index += 1
    reply = " ".join("".join(pieces).split())
    return reply[:1].upper() + reply[1:]


def restated_words(arguments, bindings):
    words = []
    for argument in arguments:
        if is_reference(argument):
            words.extend(binding(bindings, int(argument[1])))
        else:
            words.append(argument)
    return words


def eliza_lines(text):
    words = text.split()
    lines = [FIRST_PREFIX + words[0]]
    for word in words[1:]:
        if len(lines[-1]) + 1 + len(word) <= LINE_WIDTH:
            lines[-1] += " " + word
        else:
            lines.append(CONTINUATION_PREFIX + word)
    return lines
