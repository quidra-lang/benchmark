"""Integer Harris responses with clamped Sobel gradients and raster tie breaks."""

from filters import clamped


def harris_corners(gx, gy, window, threshold, maximum):
    height = len(gx)
    width = len(gx[0])
    half = window // 2
    response = [[0] * width for _ in range(height)]
    for y in range(height):
        for x in range(width):
            xx = yy = xy = 0
            for dy in range(-half, half + 1):
                for dx in range(-half, half + 1):
                    gxx = clamped(gx, x + dx, y + dy)
                    gyy = clamped(gy, x + dx, y + dy)
                    xx += gxx * gxx
                    yy += gyy * gyy
                    xy += gxx * gyy
            response[y][x] = xx * yy - xy * xy - (xx + yy) ** 2 // 25
    candidates = []
    for y in range(height):
        for x in range(width):
            value = response[y][x]
            if value < threshold:
                continue
            keep = True
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < width and 0 <= ny < height) or (dx == dy == 0):
                        continue
                    other_value = response[ny][nx]
                    if other_value > value or (
                        other_value == value and (ny, nx) < (y, x)
                    ):
                        keep = False
                        break
                if not keep:
                    break
            if keep:
                candidates.append({
                    "x": x, "y": y, "response": value,
                })
    candidates.sort(key=lambda c: (-c["response"], c["y"], c["x"]))
    chosen = candidates[:maximum]
    for i, item in enumerate(chosen, 1):
        item["number"] = i
    return response, candidates, chosen
