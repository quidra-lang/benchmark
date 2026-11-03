"""Symmetric similarities and oriented Slope One differences."""

from math import sqrt


def pair(first, second):
    return (first, second) if first < second else (second, first)


def largest_neighbors(candidates, size):
    """Candidates are (ID, similarity); ID resolves every similarity tie."""
    return sorted(candidates, key=lambda candidate: (-candidate[1], candidate[0]))[:size]


class Neighborhood:
    def __init__(self, data, shrinkage):
        self.user = {}
        self.item = {}
        self.counts = {}
        self.differences = {}
        self.shrinkage = shrinkage
        self.build_users(data)
        self.build_items(data)

    def build_users(self, data):
        for position, user in enumerate(data.users):
            left = data.by_user[user]
            for other in data.users[position + 1:]:
                right = data.by_user[other]
                common = [item for item in left if item in right]
                count = len(common)
                if count < 2:
                    continue
                sx = sy = sxx = syy = sxy = 0
                for item in common:
                    x, y = left[item], right[item]
                    sx += x
                    sy += y
                    sxx += x * x
                    syy += y * y
                    sxy += x * y
                numerator = count * sxy - sx * sy
                dx = count * sxx - sx * sx
                dy = count * syy - sy * sy
                if dx == 0 or dy == 0:
                    continue
                a = (numerator * count) * (numerator * count)
                b = dx * dy * (count + self.shrinkage) * (count + self.shrinkage)
                sign = 1 if numerator > 0 else -1 if numerator < 0 else 0
                self.user[user, other] = (sign * sqrt(a / b), count)

    def build_items(self, data):
        for position, item in enumerate(data.items):
            left = data.by_item[item]
            for other in data.items[position + 1:]:
                right = data.by_item[other]
                common = [user for user in left if user in right]
                count = len(common)
                if not count:
                    continue
                difference = 0
                for user in common:
                    difference += left[user] - right[user]
                self.counts[item, other] = count
                self.differences[item, other] = difference
                if count < 2:
                    continue
                numerator = left_norm = right_norm = 0.0
                for user in common:
                    x = left[user] - data.user_means[user]
                    y = right[user] - data.user_means[user]
                    numerator += x * y
                    left_norm += x * x
                    right_norm += y * y
                if left_norm == 0 or right_norm == 0:
                    continue
                similarity = numerator / sqrt(left_norm * right_norm)
                similarity = similarity * count / (count + self.shrinkage)
                self.item[item, other] = (similarity, count)

    def user_similarity(self, user, other):
        return self.user.get(pair(user, other))

    def item_similarity(self, item, other):
        return self.item.get(pair(item, other))

    def common_count(self, item, other):
        return self.counts.get(pair(item, other), 0)

    def difference(self, target, source):
        value = self.differences.get(pair(target, source), 0)
        return value if target < source else -value

    def deviation(self, target, source):
        count = self.common_count(target, source)
        return self.difference(target, source) / (count + self.shrinkage)
