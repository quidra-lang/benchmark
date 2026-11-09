values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]
for target in [42, 3, 77, 31, 50, 1]:
    lo, hi, found = 0, len(values) - 1, -1
    probes = []
    while lo <= hi:
        mid = (lo + hi) // 2
        probes.append(mid)
        if values[mid] == target:
            found = mid
            break
        if values[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    result = f"index {found}" if found >= 0 else "not found"
    print(f"{target}: probes {' '.join(map(str, probes))} -> {result}")
