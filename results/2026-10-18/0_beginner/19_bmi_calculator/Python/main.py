people = [
    ("Aiko", 158, 45),
    ("Kenji", 172, 68),
    ("Mika", 165, 70),
    ("Ryo", 180, 101),
    ("Yuki", 150, 52),
]
for name, height, weight in people:
    bmi = weight * 10000 / (height * height)
    if bmi < 18.5:
        category = "underweight"
    elif bmi < 25:
        category = "normal"
    elif bmi < 30:
        category = "overweight"
    else:
        category = "obese"
    print(f"{name}: BMI {bmi:.1f} ({category})")
