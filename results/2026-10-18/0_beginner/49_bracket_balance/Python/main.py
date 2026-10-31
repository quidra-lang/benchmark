strings = [
    "(a + b) * [c - d]",
    "{x = [1, 2, (3 + 4)]}",
    "f(a[i] + g(b)}",
    "(1 + 2)) * 3",
    "if (a < b) { c = d[0]; }",
    "((a + b] * c",
    "[{(x * y) - z}",
]
matching = {")": "(", "]": "[", "}": "{"}
for text in strings:
    stack = []
    error = None
    for index, char in enumerate(text):
        if char in "([{":
            stack.append(char)
        elif char in matching:
            if not stack or stack[-1] != matching[char]:
                error = index
                break
            stack.pop()
    if error is None and stack:
        error = len(text)
    result = "balanced" if error is None else f"error at index {error}"
    print(f"{text} -> {result}")
