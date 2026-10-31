import string


BASE64_ALPHABET = string.ascii_uppercase + string.ascii_lowercase + string.digits + "+/"


def strict_base64(text):
    if len(text) % 4 != 0:
        return None
    data = text.rstrip("=")
    if len(text) - len(data) >= 3:
        return None
    result = bytearray()
    buffer = 0
    bits = 0
    for char in data:
        value = BASE64_ALPHABET.find(char)
        if value < 0:
            return None
        buffer = buffer << 6 | value
        bits += 6
        if bits >= 8:
            bits -= 8
            result.append(buffer >> bits)
            buffer &= (1 << bits) - 1
    return bytes(result)


def decode_base64_body(text):
    compact = text.replace(" ", "").replace("\t", "").replace("\n", "")
    data = strict_base64(compact)
    if data is None:
        return None
    data = data.replace(b"\r\n", b"\n")
    if not all(byte in (9, 10) or 32 <= byte <= 126 for byte in data):
        return None
    return data.decode("ascii")


def escaped_char(line, position):
    digits = line[position + 1:position + 3]
    if len(digits) == 2 and all(digit in string.hexdigits for digit in digits):
        value = int(digits, 16)
        if value == 9 or 32 <= value <= 126:
            return chr(value)
    return None


def decode_quoted_printable(text):
    output = []
    error = False
    lines = text.split("\n")
    for index, line in enumerate(lines):
        line = line.rstrip(" \t")
        soft_break = line.endswith("=")
        if soft_break:
            line = line[:-1]
        position = 0
        while position < len(line):
            char = line[position]
            decoded = escaped_char(line, position) if char == "=" else None
            if decoded is not None:
                output.append(decoded)
                position += 3
            else:
                output.append(char)
                error = error or char == "="
                position += 1
        if not soft_break and index < len(lines) - 1:
            output.append("\n")
    return "".join(output), error
