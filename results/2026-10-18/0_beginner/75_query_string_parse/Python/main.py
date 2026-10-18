def decode(text):
    result = ""
    i = 0
    while i < len(text):
        if text[i] == "+":
            result += " "
        elif text[i] == "%":
            result += chr(int(text[i + 1:i + 3], 16))
            i += 2
        else:
            result += text[i]
        i += 1
    return result


queries = [
    "name=Alice+Smith&age=30&city=New%20York",
    "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
    "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
    "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips",
]
for number, query in enumerate(queries, 1):
    values = {}
    for item in query.split("&"):
        key, _, value = item.partition("=")
        values.setdefault(decode(key), []).append(decode(value))
    print(f"query {number}:")
    for key in sorted(values):
        quoted = ", ".join(f'"{value}"' for value in values[key])
        print(f"  {key}: {quoted}")
