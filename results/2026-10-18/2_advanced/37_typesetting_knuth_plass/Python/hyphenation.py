"""Dictionary and explicit-hyphen split points in ASCII words."""


def is_letter(character):
    return "A" <= character <= "Z" or "a" <= character <= "z"


class Hyphenation:
    def __init__(self, dictionary_lines, additions, left_min, right_min):
        self.words = {}
        self.left_min = left_min
        self.right_min = right_min
        for spelling in dictionary_lines:
            self.register(spelling)
        for spelling in additions:
            self.register(spelling)

    def register(self, spelling):
        parts = spelling.split("-")
        position = 0
        points = []
        for part in parts[:-1]:
            position += len(part)
            points.append(position)
        self.words["".join(parts)] = points

    def split_points(self, word):
        points = {}
        first = 0
        while first < len(word) and not is_letter(word[first]):
            first += 1
        last = len(word)
        while last > first and not is_letter(word[last - 1]):
            last -= 1
        core = word[first:last]
        if core and all(is_letter(character) for character in core):
            for position in self.words.get(core.lower(), ()):
                if (position >= self.left_min
                        and len(core) - position >= self.right_min):
                    points[first + position] = True
        for position in range(1, len(word) - 1):
            if (word[position] == "-" and is_letter(word[position - 1])
                    and is_letter(word[position + 1])):
                points[position + 1] = False
        return sorted(points.items())
