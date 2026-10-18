students = [("Tanaka", [78, 85, 94]), ("Suzuki", [88, 74, 82]), ("Yamada", [65, 90, 71]), ("Ito", [80, 79, 85]), ("Kato", [92, 88, 95]), ("Mori", [70, 62, 78])]
records = sorted(((name, sum(scores)) for name, scores in students), key=lambda row: (-row[1], row[0]))
previous = None
rank = 0
for index, (name, total) in enumerate(records, 1):
    if total != previous:
        rank = index
    average = total / 3
    print(f"{rank}. {name} total={total} average={average:.2f}")
    previous = total
