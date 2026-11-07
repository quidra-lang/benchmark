from baskets import contains


class CandidateLevel:
    def __init__(self, joined, excluded, pruned, itemsets):
        self.joined = joined
        self.excluded = excluded
        self.pruned = pruned
        self.itemsets = itemsets


def one_smaller_subsets(itemset):
    return [itemset[:index] + itemset[index + 1:] for index in range(len(itemset))]


def join_level(previous):
    ordered = sorted(previous)
    joined = []
    for index, first in enumerate(ordered):
        for second in ordered[index + 1:]:
            if first[:-1] != second[:-1]:
                break
            joined.append(first + second[-1:])
    return joined


def is_taxonomy_pair(candidate, taxonomy):
    first, second = candidate
    return taxonomy.get(first) == second or taxonomy.get(second) == first


def has_infrequent_subset(candidate, previous):
    return any(subset not in previous for subset in one_smaller_subsets(candidate))


def generate_candidates(previous, size, taxonomy=None):
    joined = join_level(previous)
    remaining = joined
    if taxonomy is not None and size == 2:
        remaining = [
            candidate for candidate in joined if not is_taxonomy_pair(candidate, taxonomy)
        ]
    known = set(previous)
    survivors = [
        candidate for candidate in remaining if not has_infrequent_subset(candidate, known)
    ]
    return CandidateLevel(
        len(joined), len(joined) - len(remaining), len(remaining) - len(survivors), survivors
    )


def count_supports(item_sets, itemsets):
    counts = dict.fromkeys(itemsets, 0)
    by_first_item = {}
    for itemset in counts:
        by_first_item.setdefault(itemset[0], []).append(itemset)
    for items in item_sets:
        for item in items:
            for itemset in by_first_item.get(item, ()):
                if contains(items, itemset):
                    counts[itemset] += 1
    return counts
