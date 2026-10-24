terms = [1, 1]
while len(terms) < 30:
    terms.append(terms[-1] + terms[-2])
print(*terms)
print(f"sum: {sum(terms)}")
