from scoring import ALPHABET, is_letter, letter_value


AFFINE_MULTIPLIERS = (1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25)


def letter_values(text):
    return [letter_value(character) for character in text if is_letter(character)]


def replace_letters(text, values):
    result = []
    index = 0
    for character in text:
        if is_letter(character):
            letter = ALPHABET[values[index]]
            result.append(letter if character.isupper() else letter.lower())
            index += 1
        else:
            result.append(character)
    return "".join(result)


def caesar_encrypt(text, shift):
    return replace_letters(text, [(value + shift) % 26 for value in letter_values(text)])


def caesar_decrypt(text, shift):
    return replace_letters(text, [(value - shift) % 26 for value in letter_values(text)])


def modular_inverse(multiplier):
    return next(inverse for inverse in range(1, 26) if multiplier * inverse % 26 == 1)


def affine_encrypt(text, key):
    multiplier, offset = key
    values = [(multiplier * value + offset) % 26 for value in letter_values(text)]
    return replace_letters(text, values)


def affine_decrypt(text, key):
    multiplier, offset = key
    inverse = modular_inverse(multiplier)
    values = [inverse * (value - offset) % 26 for value in letter_values(text)]
    return replace_letters(text, values)


def vigenere_encrypt(text, key):
    shifts = letter_values(key)
    values = [
        (value + shifts[index % len(shifts)]) % 26
        for index, value in enumerate(letter_values(text))
    ]
    return replace_letters(text, values)


def vigenere_decrypt(text, key):
    shifts = letter_values(key)
    values = [
        (value - shifts[index % len(shifts)]) % 26
        for index, value in enumerate(letter_values(text))
    ]
    return replace_letters(text, values)


def autokey_encrypt(text, key):
    shifts = letter_values(key)
    plain = letter_values(text)
    values = []
    for index, value in enumerate(plain):
        shift = shifts[index] if index < len(shifts) else plain[index - len(shifts)]
        values.append((value + shift) % 26)
    return replace_letters(text, values)


def autokey_decrypt(text, key):
    shifts = letter_values(key)
    values = []
    for index, value in enumerate(letter_values(text)):
        shift = shifts[index] if index < len(shifts) else values[index - len(shifts)]
        values.append((value - shift) % 26)
    return replace_letters(text, values)
