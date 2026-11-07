alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for text in ["Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"]:
    encoded = ""
    for start in range(0, len(text), 3):
        chunk = [ord(char) for char in text[start : start + 3]]
        size = len(chunk)
        chunk += [0] * (3 - size)
        value = (chunk[0] << 16) | (chunk[1] << 8) | chunk[2]
        symbols = "".join(alphabet[(value >> shift) & 63] for shift in [18, 12, 6, 0])
        encoded += symbols[: size + 1] + "=" * (3 - size)
    print(f'"{text}" -> "{encoded}"')
