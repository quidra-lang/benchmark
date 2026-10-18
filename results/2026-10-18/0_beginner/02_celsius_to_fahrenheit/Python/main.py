temperatures = [-40, -15, -3, 0, 22, 37, 100]
for celsius in temperatures:
    fahrenheit = celsius * 9 / 5 + 32
    print(f"{celsius} C = {fahrenheit:.1f} F")
