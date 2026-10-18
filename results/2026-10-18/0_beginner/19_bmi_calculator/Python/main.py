from decimal import Decimal, ROUND_HALF_UP

people = [("Aiko", 158, 45), ("Kenji", 172, 68), ("Mika", 165, 70), ("Ryo", 180, 101), ("Yuki", 150, 52)]
for name, height, weight in people:
    bmi = Decimal(weight * 10000) / (height * height)
    category = "underweight" if bmi < Decimal("18.5") else "normal" if bmi < 25 else "overweight" if bmi < 30 else "obese"
    rounded = bmi.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    print(f"{name}: BMI {rounded} ({category})")
