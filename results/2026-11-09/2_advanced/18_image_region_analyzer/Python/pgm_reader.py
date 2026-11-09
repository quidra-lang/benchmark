class Image:
    def __init__(self, name, width, height, maxval, pixels):
        self.name = name
        self.width = width
        self.height = height
        self.maxval = maxval
        self.pixels = pixels


def read_words(path):
    words = []
    with open(path) as file:
        for line in file:
            words.extend(line.partition("#")[0].split())
    return words


def read_images(path):
    words = read_words(path)
    images = []
    position = 0
    while position < len(words):
        name = words[position + 1]
        width = int(words[position + 3])
        height = int(words[position + 4])
        maxval = int(words[position + 5])
        position += 6
        values = [int(word) for word in words[position:position + width * height]]
        position += width * height
        pixels = [values[y * width:(y + 1) * width] for y in range(height)]
        images.append(Image(name, width, height, maxval, pixels))
    return images
