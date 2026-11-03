import re


WORD_PATTERN = re.compile("[a-z0-9]+")
BIGRAM_JOINER = "_"


def extract_words(text):
    return WORD_PATTERN.findall(text.lower())


def is_bigram(term):
    return BIGRAM_JOINER in term


class Tokens:
    def __init__(self, text, stopwords):
        raw_words = extract_words(text)
        self.raw_count = len(raw_words)
        self.stopword_count = 0
        self.short_count = 0
        self.words = []
        for word in raw_words:
            if word in stopwords:
                self.stopword_count += 1
            elif len(word) == 1:
                self.short_count += 1
            else:
                self.words.append(word)
        self.bigrams = [
            first + BIGRAM_JOINER + second for first, second in zip(self.words, self.words[1:])
        ]
        self.bigram_terms = self.words + self.bigrams

    def terms(self, use_bigrams):
        if use_bigrams:
            return self.bigram_terms
        return self.words
