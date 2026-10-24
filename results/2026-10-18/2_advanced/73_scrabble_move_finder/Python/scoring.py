"""Move squares, perpendicular words and premiums used only by new tiles."""

from board import PREMIUMS, run_at


RACK_SIZE, BINGO_BONUS = 7, 50


def squares(move):
    return [(move.row + move.direction * offset, move.column + (1 - move.direction) * offset, letter)
            for offset, letter in enumerate(move.word)]


def placement(board, move):
    return [(row, column, letter) for row, column, letter in squares(move) if board[row][column] == "."]


def apply(board, new_tiles):
    result = [row[:] for row in board]
    for row, column, letter in new_tiles:
        result[row][column] = letter
    return result


def cross_words(board, move):
    new_tiles = placement(board, move)
    after = apply(board, new_tiles)
    result = []
    for row, column, _ in new_tiles:
        word = run_at(after, row, column, 1 - move.direction)
        if len(word.word) >= 2:
            result.append(word)
    return result


def word_score(board, word, values):
    score, multiplier = 0, 1
    for row, column, letter in squares(word):
        value = values[letter] if letter.isupper() else 0
        if board[row][column] == ".":
            premium = PREMIUMS[row][column]
            value *= 2 if premium == "+" else 3 if premium == "^" else 1
            multiplier *= 2 if premium == "*" else 3 if premium == "#" else 1
        score += value
    return score * multiplier


def score_move(board, move, values):
    words = [move] + cross_words(board, move)
    scores = [word_score(board, word, values) for word in words]
    new_tiles = placement(board, move)
    score = sum(scores) + (BINGO_BONUS if len(new_tiles) == RACK_SIZE else 0)
    return score, new_tiles, list(zip(words, scores))
