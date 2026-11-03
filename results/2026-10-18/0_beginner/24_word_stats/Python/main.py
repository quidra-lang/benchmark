words = [
    "we",
    "planted",
    "beans",
    "and",
    "carrots",
    "in",
    "the",
    "garden",
    "behind",
    "our",
    "old",
    "house",
]
average = sum(map(len, words)) / len(words)
print(f"words: {len(words)}")
print(f"longest: {max(words, key=len)}")
print(f"shortest: {min(words, key=len)}")
print(f"average length: {average:.2f}")
