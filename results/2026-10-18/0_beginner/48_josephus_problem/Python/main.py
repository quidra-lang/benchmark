for n, k in [(7, 3), (10, 2), (41, 3)]:
    people = list(range(1, n + 1))
    removed = []
    index = 0
    while people:
        index = (index + k - 1) % len(people)
        removed.append(people.pop(index))
    print(f"n={n} k={k}:", *removed)
    print(f"survivor: {removed[-1]}")
