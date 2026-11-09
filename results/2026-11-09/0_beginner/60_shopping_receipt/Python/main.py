items = [
    ("milk", 198, 2, "food"),
    ("notebook", 165, 3, "general"),
    ("bread", 248, 1, "food"),
    ("apple", 128, 4, "food"),
    ("detergent", 437, 1, "general"),
    ("eggs", 268, 1, "food"),
]
totals = {"food": 0, "general": 0}
for name, price, quantity, category in items:
    subtotal = price * quantity
    totals[category] += subtotal
    print(f"{name} {price} x {quantity} = {subtotal}")
payment = sum(totals.values())
for category, rate in [("food", 8), ("general", 10)]:
    tax = totals[category] * rate // 100
    payment += tax
    print(f"{category}: {totals[category]} yen, tax {tax} yen")
print(f"total: {payment} yen")
