from collections import Counter

text = "she sells sea shells by the sea shore"
frequencies = Counter(text)
trees = [
    {"weight": count, "minimum": symbol, "symbol": symbol, "left": None, "right": None}
    for symbol, count in frequencies.items()
]
while len(trees) > 1:
    trees.sort(key=lambda tree: (tree["weight"], tree["minimum"]))
    left, right = trees.pop(0), trees.pop(0)
    trees.append(
        {
            "weight": left["weight"] + right["weight"],
            "minimum": min(left["minimum"], right["minimum"]),
            "symbol": None,
            "left": left,
            "right": right,
        }
    )
codes = {}


def visit(tree, prefix):
    if tree["symbol"] is not None:
        codes[tree["symbol"]] = prefix
    else:
        visit(tree["left"], prefix + "0")
        visit(tree["right"], prefix + "1")


visit(trees[0], "")
for symbol in sorted(frequencies):
    print(f"'{symbol}' freq={frequencies[symbol]} code={codes[symbol]}")
bits = sum(count * len(codes[symbol]) for symbol, count in frequencies.items())
print(f"encoded bits: {bits}")
print(f"fixed 8-bit: {len(text) * 8}")
