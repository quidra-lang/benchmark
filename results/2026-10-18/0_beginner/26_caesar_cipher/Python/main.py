from string import ascii_lowercase, ascii_uppercase


def caesar(text, shift):
    shifted = "".join(letters[shift:] + letters[:shift] for letters in (ascii_lowercase, ascii_uppercase))
    return text.translate(str.maketrans(ascii_lowercase + ascii_uppercase, shifted))


message = "Zoe, meet Max by the Old Bridge at six!"
encrypted = caesar(message, 3)
print(encrypted)
print(caesar(encrypted, -3))
