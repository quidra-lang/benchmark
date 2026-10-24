people = [("Aiko", 158, 45), ("Kenji", 172, 68), ("Mika", 165, 70), ("Ryo", 180, 101), ("Yuki", 150, 52)]
for name, height, weight in people:
    bmi = weight * 10000 / (height * height)
    category = "underweight" if bmi < 18.5 else "normal" if bmi < 25 else "overweight" if bmi < 30 else "obese"
    print(f"{name}: BMI {bmi:.1f} ({category})")
