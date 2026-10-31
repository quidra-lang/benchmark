from collections import Counter

sentence = "Peter Piper picked a peck of pickled peppers!"
counts = Counter(letter for letter in sentence.lower() if "a" <= letter <= "z")
for letter in sorted(counts):
    print(f"{letter}: {counts[letter]}")
