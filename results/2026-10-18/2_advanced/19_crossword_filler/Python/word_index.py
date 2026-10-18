from grid import EMPTY


UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIGITS = "0123456789"
MIN_WORD_LENGTH = 3
MAX_WORD_LENGTH = 15
MIN_SCORE = 1
MAX_SCORE = 100
MAX_CLUE_LENGTH = 60


def is_valid_word(text):
    if not MIN_WORD_LENGTH <= len(text) <= MAX_WORD_LENGTH:
        return False
    return all(letter in UPPERCASE for letter in text)


def is_valid_integer(text, low, high):
    if not text or text[0] == "0" or len(text) > len(str(high)):
        return False
    if any(digit not in DIGITS for digit in text):
        return False
    return low <= int(text) <= high


def word_line_error(line):
    if line.count(" ") != 1:
        return "bad format"
    word, score = line.split(" ")
    if not is_valid_word(word):
        return "bad word"
    if not is_valid_integer(score, MIN_SCORE, MAX_SCORE):
        return "bad score"
    return None


def clue_line_error(line):
    if line.count("|") != 1:
        return "bad format"
    word, clue = line.split("|")
    if not is_valid_word(word):
        return "bad word"
    if not 1 <= len(clue) <= MAX_CLUE_LENGTH or clue[0] == " " or clue[-1] == " ":
        return "bad clue"
    return None


def rank_order(scores):
    return sorted(scores, key=lambda word: (-scores[word], word))


def matches(word, pattern):
    return all(mark == EMPTY or mark == letter for mark, letter in zip(pattern, word))


class WordIndex:
    def __init__(self, scores):
        self.scores = scores
        self.ranked = rank_order(scores)
        self.by_length = {}
        self.by_letter = {}
        for word in self.ranked:
            self.by_length.setdefault(len(word), []).append(word)
            for position, letter in enumerate(word):
                self.by_letter.setdefault((len(word), position, letter), []).append(word)

    def pool(self, pattern):
        length = len(pattern)
        pool = self.by_length.get(length, [])
        for position, mark in enumerate(pattern):
            if mark != EMPTY:
                bucket = self.by_letter.get((length, position, mark), [])
                if len(bucket) < len(pool):
                    pool = bucket
        return pool

    def candidates(self, pattern, min_score, used):
        result = []
        for word in self.pool(pattern):
            if self.scores[word] < min_score:
                break
            if word not in used and matches(word, pattern):
                result.append(word)
        return result
