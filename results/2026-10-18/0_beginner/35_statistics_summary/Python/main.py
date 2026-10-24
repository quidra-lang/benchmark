from math import sqrt


values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71]
ordered = sorted(values)
mean = sum(values) / len(values)
squares = 0.0
for value in values:
    difference = value - mean
    squares += difference * difference
stdev = sqrt(squares / len(values))
mode = max(ordered, key=values.count)
print(f"mean: {mean:.3f}")
print(f"median: {ordered[len(values) // 2]}")
print(f"mode: {mode}")
print(f"range: {max(values) - min(values)}")
print(f"stdev: {stdev:.3f}")
