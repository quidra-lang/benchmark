triples = [(3, 8, 5), (6, 6, 6), (5, 8, 5), (13, 5, 12), (2, 9, 4), (7, 4, 7), (8, 6, 7), (4, 9, 6)]
for triple in triples:
    a, b, c = sorted(triple)
    if a + b <= c:
        result = "not a triangle"
    else:
        side = "equilateral" if a == c else "isosceles" if a == b or b == c else "scalene"
        square_sum = a * a + b * b
        angle = "acute" if c * c < square_sum else "right" if c * c == square_sum else "obtuse"
        result = f"{side} {angle}"
    print(f"{' '.join(map(str, triple))}: {result}")
