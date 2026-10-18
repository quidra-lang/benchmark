sentence = "Peter Piper picked a peck of pickled peppers!"
counts = {}
for letter in sentence.lower():
    if "a" <= letter <= "z":
        counts[letter] = counts.get(letter, 0) + 1
for letter in sorted(counts):
    print(f"{letter}: {counts[letter]}")
