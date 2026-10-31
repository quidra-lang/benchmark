scores = [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]
counts = dict.fromkeys("ABCDF", 0)
for score in scores:
    if score >= 90:
        grade = "A"
    elif score >= 80:
        grade = "B"
    elif score >= 70:
        grade = "C"
    elif score >= 60:
        grade = "D"
    else:
        grade = "F"
    counts[grade] += 1
    print(f"{score}: {grade}")
for grade, count in counts.items():
    print(f"{grade}: {count}")
