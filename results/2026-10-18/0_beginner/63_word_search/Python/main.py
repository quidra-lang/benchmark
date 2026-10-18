board = [
    "MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
    "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR",
]
directions = [("E", 0, 1), ("SE", 1, 1), ("S", 1, 0), ("SW", 1, -1),
              ("W", 0, -1), ("NW", -1, -1), ("N", -1, 0), ("NE", -1, 1)]


def find(word):
    for row in range(len(board)):
        for column in range(len(board[0])):
            for name, dr, dc in directions:
                matches = True
                for i, char in enumerate(word):
                    r, c = row + dr * i, column + dc * i
                    if not (0 <= r < len(board) and 0 <= c < len(board[0])) or board[r][c] != char:
                        matches = False
                        break
                if matches:
                    return f"({row}, {column}) {name}"
    return "not found"


for word in ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"]:
    print(f"{word}: {find(word)}")
