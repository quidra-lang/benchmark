import re
from itertools import groupby

strings = [
    "AAABBBCCCD",
    "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",
    "ALGORITHM",
    "MISSISSIPPI",
    "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ",
]
for text in strings:
    encoded = "".join(f"{sum(1 for _ in run)}{char}" for char, run in groupby(text))
    decoded = "".join(
        char * int(count) for count, char in re.findall(r"(\d+)([A-Z])", encoded)
    )
    print(f"{text} -> {encoded} -> {decoded}")
