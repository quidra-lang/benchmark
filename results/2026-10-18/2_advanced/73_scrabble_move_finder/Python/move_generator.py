"""Anchor-based Appel-Jacobson prefix and right-extension generation."""

from collections import Counter

from board import CENTER, SIZE, Move, neighbors, run_at, tiles, transpose
from scoring import apply, placement


LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def anchors(board):
    if not tiles(board):
        return {CENTER}
    return {(row, column) for row in range(SIZE) for column in range(SIZE)
            if board[row][column] == "." and any(board[r][c] != "." for r, c in neighbors(row, column))}


def cross_checks(board, trie):
    result = {}
    for row in range(SIZE):
        for column in range(SIZE):
            if board[row][column] != ".":
                continue
            first, last = row, row
            while first > 0 and board[first - 1][column] != ".":
                first -= 1
            while last + 1 < SIZE and board[last + 1][column] != ".":
                last += 1
            if first == last:
                continue
            prefix = "".join(board[r][column] for r in range(first, row)).upper()
            suffix = "".join(board[r][column] for r in range(row + 1, last + 1)).upper()
            result[row, column] = {letter for letter in LETTERS if prefix + letter + suffix in trie}
    return result


def across_moves(board, rack, trie, anchor_squares, checks):
    result, counts = [], Counter(rack)
    for row, anchor in sorted(anchor_squares):
        def extend(node, column, word, start):
            empty = column == SIZE or board[row][column] == "."
            if empty and column > anchor and node.terminal:
                result.append(Move(row, start, 0, word))
            if column == SIZE:
                return
            if not empty:
                letter = board[row][column]
                child = node.children.get(letter.upper())
                if child is not None:
                    extend(child, column + 1, word + letter, start)
                return
            allowed = checks.get((row, column))
            for letter in sorted(node.children):
                if allowed is not None and letter not in allowed:
                    continue
                child = node.children[letter]
                for tile, written in ((letter, letter), ("?", letter.lower())):
                    if counts[tile]:
                        counts[tile] -= 1
                        extend(child, column + 1, word + written, start)
                        counts[tile] += 1

        def left_part(node, prefix, remaining):
            extend(node, anchor, prefix, anchor - len(prefix))
            if remaining == 0:
                return
            for letter in sorted(node.children):
                for tile, written in ((letter, letter), ("?", letter.lower())):
                    if counts[tile]:
                        counts[tile] -= 1
                        left_part(node.children[letter], prefix + written, remaining - 1)
                        counts[tile] += 1

        if anchor > 0 and board[row][anchor - 1] != ".":
            first = anchor - 1
            while first > 0 and board[row][first - 1] != ".":
                first -= 1
            prefix = "".join(board[row][first:anchor])
            node = trie.prefix(prefix.upper())
            if node is not None:
                extend(node, anchor, prefix, first)
        else:
            first = anchor - 1
            while first >= 0 and board[row][first] == "." and (row, first) not in anchor_squares:
                first -= 1
            left_part(trie.root, "", anchor - first - 1)
    return result


def generate(board, rack, trie):
    anchor_squares = anchors(board)
    across = across_moves(board, rack, trie, anchor_squares, cross_checks(board, trie))
    transposed = transpose(board)
    down = across_moves(transposed, rack, trie, {(column, row) for row, column in anchor_squares},
                        cross_checks(transposed, trie))
    result = {}
    for move in across + [Move(move.column, move.row, 1, move.word) for move in down]:
        new_tiles = placement(board, move)
        if len(new_tiles) == 1 and move.direction == 1:
            row, column, _ = new_tiles[0]
            if len(run_at(apply(board, new_tiles), row, column, 0).word) >= 2:
                continue
        result[tuple(sorted(new_tiles))] = move
    return list(result.values())
