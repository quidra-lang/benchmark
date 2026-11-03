values = [7, 98000, 4096, 50301, 2718281, 123456789]
for value in values:
    digits = str(value)
    digit_sum = sum(map(int, digits))
    reversed_value = int(digits[::-1])
    print(f"{value}: digits={len(digits)} sum={digit_sum} reversed={reversed_value}")
