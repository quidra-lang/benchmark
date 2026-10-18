games = [
    [8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2],
    [3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5],
    [5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5],
    [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
    [10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10],
]
for number, rolls in enumerate(games, 1):
    index = total = 0
    cumulative = []
    for frame in range(9):
        if rolls[index] == 10:
            total += 10 + rolls[index + 1] + rolls[index + 2]
            index += 1
        else:
            score = rolls[index] + rolls[index + 1]
            total += score + (rolls[index + 2] if score == 10 else 0)
            index += 2
        cumulative.append(total)
    total += sum(rolls[index:])
    cumulative.append(total)
    print(f"game {number}:", *cumulative)
