symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.".split()
table = dict(zip(symbols, codes))
reverse = {code: symbol for symbol, code in table.items()}
message = "MEET ME AT PIER 9 AT 1745"
encoded = " / ".join(" ".join(table[char] for char in word) for word in message.split(" "))
decoded = " ".join("".join(reverse[code] for code in word.split(" ")) for word in encoded.split(" / "))
print(encoded)
print(decoded)
