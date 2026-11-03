"""Board geometry, premium squares, words, connectivity and display."""

from collections import namedtuple
import re


SIZE, CENTER = 15, (7, 7)
COLUMNS = "ABCDEFGHIJKLMNO"
Move = namedtuple("Move", "row column direction word")
PREMIUMS = [row.split() for row in (
    "# . . + . . . # . . . + . . #",
    ". * . . . ^ . . . ^ . . . * .",
    ". . * . . . + . + . . . * . .",
    "+ . . * . . . + . . . * . . +",
    ". . . . * . . . . . * . . . .",
    ". ^ . . . ^ . . . ^ . . . ^ .",
    ". . + . . . + . + . . . + . .",
    "# . . + . . . * . . . + . . #",
    ". . + . . . + . + . . . + . .",
    ". ^ . . . ^ . . . ^ . . . ^ .",
    ". . . . * . . . . . * . . . .",
    "+ . . * . . . + . . . * . . +",
    ". . * . . . + . + . . . * . .",
    ". * . . . ^ . . . ^ . . . * .",
    "# . . + . . . # . . . + . . #",
)]


def inside(row, column):
    return 0 <= row < SIZE and 0 <= column < SIZE


def square_name(row, column):
    return f"{COLUMNS[column]}{row + 1}"


def position(move):
    return f"{COLUMNS[move.column]}{move.row + 1}" if move.direction else f"{move.row + 1}{COLUMNS[move.column]}"


def parse_position(text):
    if re.fullmatch(r"([1-9]|1[0-5])[A-O]", text):
        return int(text[:-1]) - 1, COLUMNS.index(text[-1]), 0
    if re.fullmatch(r"[A-O]([1-9]|1[0-5])", text):
        return int(text[1:]) - 1, COLUMNS.index(text[0]), 1
    return None


def transpose(board):
    return [list(row) for row in zip(*board)]


def transpose_tiles(tiles):
    return [(column, row, letter) for row, column, letter in tiles]


def tiles(board):
    return [(row, column, letter) for row, values in enumerate(board)
            for column, letter in enumerate(values) if letter != "."]


def neighbors(row, column):
    return [(r, c) for r, c in ((row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1))
            if inside(r, c)]


def run_at(board, row, column, direction):
    dr, dc = direction, 1 - direction
    while inside(row - dr, column - dc) and board[row - dr][column - dc] != ".":
        row, column = row - dr, column - dc
    first_row, first_column, letters = row, column, []
    while inside(row, column) and board[row][column] != ".":
        letters.append(board[row][column])
        row, column = row + dr, column + dc
    return Move(first_row, first_column, direction, "".join(letters))


def words(board):
    result = []
    for direction in (0, 1):
        for line in range(SIZE):
            offset = 0
            while offset < SIZE:
                row, column = (line, offset) if direction == 0 else (offset, line)
                if board[row][column] == ".":
                    offset += 1
                    continue
                word = run_at(board, row, column, direction)
                if len(word.word) >= 2:
                    result.append(word)
                offset += len(word.word)
    return result


def connected(board):
    occupied = {(row, column) for row, column, _ in tiles(board)}
    if not occupied:
        return True
    pending = [next(iter(occupied))]
    seen = set(pending)
    while pending:
        for neighbor in neighbors(*pending.pop()):
            if neighbor in occupied and neighbor not in seen:
                seen.add(neighbor)
                pending.append(neighbor)
    return seen == occupied


def display(board):
    lines = ["   " + " ".join(COLUMNS)]
    for row, values in enumerate(board):
        letters = [PREMIUMS[row][column] if letter == "." else letter for column, letter in enumerate(values)]
        lines.append(f"{row + 1:2d} " + " ".join(letters))
    return lines
