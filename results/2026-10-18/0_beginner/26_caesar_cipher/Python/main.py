def caesar(text, shift):
    result = []
    for char in text:
        if "A" <= char <= "Z" or "a" <= char <= "z":
            base = ord("A") if char <= "Z" else ord("a")
            char = chr(base + (ord(char) - base + shift) % 26)
        result.append(char)
    return "".join(result)


message = "Zoe, meet Max by the Old Bridge at six!"
encrypted = caesar(message, 3)
print(encrypted)
print(caesar(encrypted, -3))
