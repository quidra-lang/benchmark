cache = []
hits = misses = 0
for key in ["B", "A", "C", "B", "D", "A", "B", "E", "A", "D", "D", "C", "A", "E", "B"]:
    if key in cache:
        hits += 1
        cache.remove(key)
        result = "hit"
    else:
        misses += 1
        result = "miss"
        if len(cache) == 3:
            result += f", evict {cache.pop()}"
    cache.insert(0, key)
    print(f"{key}: {result} [{' '.join(cache)}]")
print(f"hits: {hits} misses: {misses}")
