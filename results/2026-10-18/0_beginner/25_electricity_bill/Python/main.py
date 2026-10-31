households = [
    ("Sato", 85),
    ("Suzuki", 120),
    ("Takahashi", 254),
    ("Tanaka", 300),
    ("Ito", 438),
    ("Watanabe", 176),
]
total = 0
for name, usage in households:
    bill = (
        900
        + min(usage, 120) * 30
        + max(0, min(usage, 300) - 120) * 36
        + max(0, usage - 300) * 40
    )
    total += bill
    print(f"{name}: {usage} kWh, {bill} yen")
print(f"total: {total} yen")
