from math import sqrt

for a, b, c in [
    (1, -3, -10),
    (-2, 5, 4),
    (3, 1, -2),
    (4, -12, 9),
    (1, 2, 5),
    (-2, 3, -4),
]:
    discriminant = b * b - 4 * a * c
    if discriminant > 0:
        roots = [
            (-b + sqrt(discriminant)) / (2 * a),
            (-b - sqrt(discriminant)) / (2 * a),
        ]
        result = f"x1 = {max(roots):.4f}, x2 = {min(roots):.4f}"
    elif discriminant == 0:
        result = f"x = {-b / (2 * a):.4f}"
    else:
        real = f"{-b / (2 * a):.4f}"
        imaginary = f"{sqrt(-discriminant) / (2 * abs(a)):.4f}"
        result = f"x = {real} + {imaginary}i, {real} - {imaginary}i"
    print(f"{a} {b} {c}: {result}")
