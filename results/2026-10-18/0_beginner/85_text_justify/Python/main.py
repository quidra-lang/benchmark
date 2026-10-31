from textwrap import wrap

paragraph = (
    "Good software is written for people first and for machines second. "
    "A clear program explains its purpose through careful names, small functions and honest tests. "
    "When a team agrees on shared rules for internationalization, documentation and code review, "
    "every newcomer can read the code quickly, change it safely and ship new improvements "
    "with confidence instead of fear, week after week."
)
width = 30
lines = [line.split() for line in wrap(paragraph, width)]
for index, words in enumerate(lines):
    if index == len(lines) - 1 or len(words) == 1:
        text = " ".join(words).ljust(width)
    else:
        base, extra = divmod(width - sum(map(len, words)), len(words) - 1)
        text = words[0]
        for gap, word in enumerate(words[1:]):
            text += " " * (base + (gap < extra)) + word
    print(f"|{text}|")
