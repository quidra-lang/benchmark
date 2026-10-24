words = "listen stone night silent notes apple thing enlist earth onset heart tones".split()
groups = {}
for word in words:
    key = "".join(sorted(word))
    groups.setdefault(key, []).append(word)
for group in groups.values():
    print(*group)
