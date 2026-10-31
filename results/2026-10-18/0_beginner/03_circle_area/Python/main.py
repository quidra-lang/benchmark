pi = 3.141592653589793
for radius in [3, 7, 12, 25, 41]:
    area = pi * radius * radius
    circumference = 2 * pi * radius
    print(f"r={radius} area={area:.3f} circumference={circumference:.3f}")
