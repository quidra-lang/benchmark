import re
from collections import Counter

text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."
counts = Counter(re.findall(r"[a-z]+", text.lower()))
top = sorted(counts, key=lambda word: (-counts[word], word))[:5]
for word in top:
    print(f"{word}: {counts[word]}")
print(f"distinct words: {len(counts)}")
