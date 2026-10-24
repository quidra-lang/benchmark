SQUARE_LETTERS = "ABCDEFGHIKLMNOPQRSTUVWXYZ"
SIZE = 5


def build_square(key):
    square = ""
    for letter in key + SQUARE_LETTERS:
        if letter not in square:
            square += letter
    return square


def plaintext_pairs(text):
    text = text.replace("J", "I")
    pairs = []
    index = 0
    while index < len(text):
        first = text[index]
        if index + 1 < len(text) and text[index + 1] != first:
            pairs.append(first + text[index + 1])
            index += 2
        else:
            pairs.append(first + ("Q" if first == "X" else "X"))
            index += 1
    return pairs


def ciphertext_pairs(text):
    text = text.replace("J", "I")
    return [text[index:index + 2] for index in range(0, len(text), 2)]


def is_valid_ciphertext(text):
    text = text.replace("J", "I")
    if len(text) % 2 != 0:
        return False
    return all(text[index] != text[index + 1] for index in range(0, len(text), 2))


def transform(square, pairs, step):
    result = []
    for pair in pairs:
        row_a, column_a = divmod(square.index(pair[0]), SIZE)
        row_b, column_b = divmod(square.index(pair[1]), SIZE)
        if row_a == row_b:
            column_a = (column_a + step) % SIZE
            column_b = (column_b + step) % SIZE
        elif column_a == column_b:
            row_a = (row_a + step) % SIZE
            row_b = (row_b + step) % SIZE
        else:
            column_a, column_b = column_b, column_a
        result.append(square[row_a * SIZE + column_a] + square[row_b * SIZE + column_b])
    return "".join(result)


def encrypt(text, key):
    return transform(build_square(key), plaintext_pairs(text), 1)


def decrypt(text, key):
    return transform(build_square(key), ciphertext_pairs(text), SIZE - 1)
