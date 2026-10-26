values = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14]


def merge_sort(left, right):
    if left == right:
        return 0
    middle = (left + right) // 2
    inversions = merge_sort(left, middle) + merge_sort(middle + 1, right)
    a, b = values[left : middle + 1], values[middle + 1 : right + 1]
    i = j = 0
    merged = []
    while i < len(a) and j < len(b):
        if a[i] < b[j]:
            merged.append(a[i])
            i += 1
        else:
            merged.append(b[j])
            j += 1
            inversions += len(a) - i
    merged.extend(a[i:])
    merged.extend(b[j:])
    values[left : right + 1] = merged
    print(f"merge [{left}..{right}]:", *merged)
    return inversions


inversions = merge_sort(0, len(values) - 1)
print("sorted:", *values)
print(f"inversions: {inversions}")
