scores = [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]
counts = dict.fromkeys("ABCDF", 0)
for score in scores:
    grade = "A" if score >= 90 else "B" if score >= 80 else "C" if score >= 70 else "D" if score >= 60 else "F"
    counts[grade] += 1
    print(f"{score}: {grade}")
for grade, count in counts.items():
    print(f"{grade}: {count}")
