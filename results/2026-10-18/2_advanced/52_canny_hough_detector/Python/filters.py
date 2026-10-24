"""Clamp-border integer smoothing and Sobel horizontal/vertical gradients."""


def clamped(image, x, y):
    height = len(image)
    width = len(image[0])
    x = min(max(x, 0), width - 1)
    y = min(max(y, 0), height - 1)
    return image[y][x]


def smoothing(image, params):
    height = len(image)
    width = len(image[0])
    size = params["gauss_size"]
    half = size // 2
    weights = params["gauss_kernel"]
    divisor = params["gauss_divisor"]
    output = []
    for y in range(height):
        row = []
        for x in range(width):
            total = 0
            for j in range(size):
                for i in range(size):
                    total += weights[j * size + i] * clamped(
                        image, x + i - half, y + j - half
                    )
            row.append(total // divisor)
        output.append(row)
    return output


def gradient(smoothed):
    """Sobel gx, gy and L1 magnitude at every pixel."""
    height = len(smoothed)
    width = len(smoothed[0])
    gx = [[0] * width for _ in range(height)]
    gy = [[0] * width for _ in range(height)]
    magnitude = [[0] * width for _ in range(height)]
    for y in range(height):
        for x in range(width):
            q1 = clamped(smoothed, x - 1, y - 1)
            q2 = clamped(smoothed, x, y - 1)
            q3 = clamped(smoothed, x + 1, y - 1)
            q4 = clamped(smoothed, x - 1, y)
            q6 = clamped(smoothed, x + 1, y)
            q7 = clamped(smoothed, x - 1, y + 1)
            q8 = clamped(smoothed, x, y + 1)
            q9 = clamped(smoothed, x + 1, y + 1)
            sx = (q3 + 2 * q6 + q9) - (q1 + 2 * q4 + q7)
            sy = (q7 + 2 * q8 + q9) - (q1 + 2 * q2 + q3)
            gx[y][x] = sx
            gy[y][x] = sy
            magnitude[y][x] = abs(sx) + abs(sy)
    return gx, gy, magnitude
