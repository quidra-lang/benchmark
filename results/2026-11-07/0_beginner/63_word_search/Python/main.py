board = [
    "MMONKENBIR",
    "PMTIGERJPL",
    "TGREJEDUZI",
    "SPYUTEJDEC",
    "WKAPSIDLBN",
    "KUVNGSBPRO",
    "RIBSDACBAM",
    "YWVAUAPKAH",
    "KYCGTHHESR",
    "OCCALAOKKR",
]
directions = [
    ("E", 0, 1),
    ("SE", 1, 1),
    ("S", 1, 0),
    ("SW", 1, -1),
    ("W", 0, -1),
    ("NW", -1, -1),
    ("N", -1, 0),
    ("NE", -1, 1),
]


def find(word):
    for row in range(len(board)):
        for column in range(len(board[0])):
            for name, dr, dc in directions:
                last_row = row + dr * (len(word) - 1)
                last_column = column + dc * (len(word) - 1)
                if not (
                    0 <= last_row < len(board) and 0 <= last_column < len(board[0])
                ):
                    continue
                if all(
                    board[row + dr * i][column + dc * i] == char
                    for i, char in enumerate(word)
                ):
                    return f"({row}, {column}) {name}"
    return "not found"


for word in ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"]:
    print(f"{word}: {find(word)}")
