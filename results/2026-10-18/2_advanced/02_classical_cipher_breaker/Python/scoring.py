ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


class Weights:
    def __init__(self, monograms, bigrams):
        self.monograms = monograms
        self.bigrams = bigrams

    def monogram_fitness(self, text):
        return sum(self.monograms[letter_value(letter)] for letter in text)

    def bigram_fitness(self, text):
        values = [letter_value(letter) for letter in text]
        return sum(self.bigrams[first][second] for first, second in zip(values, values[1:]))


def parse_weights(text):
    lines = text.split("\n")
    monograms = [int(word) for word in lines[1].split(" ")]
    bigrams = [[int(word) for word in line.split(" ")] for line in lines[3:29]]
    return Weights(monograms, bigrams)


def is_letter(character):
    return "A" <= character <= "Z" or "a" <= character <= "z"


def letter_value(letter):
    return ord(letter.upper()) - ord("A")


def letter_string(text):
    return "".join(character.upper() for character in text if is_letter(character))
