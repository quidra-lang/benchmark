"""ASCII PPM, settings, supplied transform tables, and hexadecimal streams."""

from entropy import HuffmanTable


def read_ppm(path):
    with open(path, encoding="ascii") as source:
        next(source)
        width, height = map(int, next(source).split())
        next(source)
        image = []
        for _ in range(height):
            values = list(map(int, next(source).split()))
            image.append([tuple(values[3 * x:3 * x + 3]) for x in range(width)])
    return image


def write_ppm(path, image):
    with open(path, "w", encoding="ascii", newline="\n") as destination:
        destination.write(f"P3\n{len(image[0])} {len(image)}\n255\n")
        for row in image:
            destination.write(" ".join(str(value) for pixel in row for value in pixel) + "\n")


def read_params(path):
    parameters = {}
    with open(path, encoding="ascii") as source:
        for line in source:
            name, *values = line.split()
            if name in ("sampling", "huffman"):
                parameters[name] = values[0]
            elif name in ("qualities", "truncate"):
                parameters[name] = list(map(int, values))
            else:
                parameters[name] = int(values[0])
    return parameters


def read_tables(path):
    with open(path, encoding="ascii") as source:
        next(source)
        transform = [list(map(int, next(source).split())) for _ in range(8)]
        quantization = []
        for _ in range(2):
            next(source)
            quantization.append([list(map(int, next(source).split())) for _ in range(8)])
        huffman = {}
        for _ in range(4):
            _, table_class, identifier = next(source).split()
            counts = list(map(int, next(source).split()))
            symbols = list(map(int, next(source).split()))
            huffman[int(table_class), int(identifier)] = HuffmanTable(counts, symbols)
    return transform, quantization, huffman


def read_hex(path):
    with open(path, encoding="ascii") as source:
        return bytes.fromhex("".join(line.strip() for line in source))


def write_hex(path, data):
    with open(path, "w", encoding="ascii", newline="\n") as destination:
        for offset in range(0, len(data), 32):
            destination.write(data[offset:offset + 32].hex() + "\n")
