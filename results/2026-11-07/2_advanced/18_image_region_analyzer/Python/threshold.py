from functools import cmp_to_key


MAX_ISODATA_ITERATIONS = 100


class Histogram:
    def __init__(self, image):
        self.maxval = image.maxval
        self.pixels = image.width * image.height
        self.counts = [0] * (image.maxval + 1)
        for row in image.pixels:
            for value in row:
                self.counts[value] += 1
        self.below_counts = []
        self.below_sums = []
        count = 0
        total = 0
        for value, frequency in enumerate(self.counts):
            count += frequency
            total += value * frequency
            self.below_counts.append(count)
            self.below_sums.append(total)
        self.total = total
        present = [value for value, frequency in enumerate(self.counts) if frequency > 0]
        self.minimum = present[0]
        self.maximum = present[-1]
        self.levels = len(present)
        self.median = next(
            value for value in range(self.maxval + 1)
            if 2 * self.below_counts[value] >= self.pixels
        )
        self.mode = self.counts.index(max(self.counts))
        self.bin_width = (self.maxval + 8) // 8
        self.bins = [
            sum(self.counts[start:start + self.bin_width])
            for start in range(0, self.maxval + 1, self.bin_width)
        ]

    def split(self, cutoff):
        below = self.below_counts[cutoff]
        sum_below = self.below_sums[cutoff]
        return below, sum_below, self.pixels - below, self.total - sum_below


class Candidate:
    def __init__(self, cutoff, below, sum_below, above, sum_above):
        self.cutoff = cutoff
        self.below = below
        self.sum_below = sum_below
        self.above = above
        self.sum_above = sum_above
        self.numerator = sum_below * sum_below * above + sum_above * sum_above * below
        self.denominator = below * above


class OtsuResult:
    def __init__(self, cutoff, upper, candidates):
        self.cutoff = cutoff
        self.upper = upper
        self.candidates = candidates


def compare_scores(first, second):
    first_quotient, first_remainder = divmod(first.numerator, first.denominator)
    second_quotient, second_remainder = divmod(second.numerator, second.denominator)
    if first_quotient != second_quotient:
        return 1 if first_quotient > second_quotient else -1
    left = first_remainder * second.denominator
    right = second_remainder * first.denominator
    if left != right:
        return 1 if left > right else -1
    return 0


def rank_order(first, second):
    order = compare_scores(second, first)
    if order != 0:
        return order
    return first.cutoff - second.cutoff


def otsu(histogram):
    candidates = []
    for cutoff in range(histogram.maxval):
        below, sum_below, above, sum_above = histogram.split(cutoff)
        if histogram.counts[cutoff] > 0 and above > 0:
            candidates.append(Candidate(cutoff, below, sum_below, above, sum_above))
    ranked = sorted(candidates, key=cmp_to_key(rank_order))
    if not ranked:
        return OtsuResult(histogram.minimum, histogram.minimum, ranked)
    best = ranked[0].cutoff
    following = next(
        value for value in range(best + 1, histogram.maxval + 1)
        if histogram.counts[value] > 0
    )
    return OtsuResult(best, following - 1, ranked)


def isodata(histogram):
    cutoff = histogram.total // histogram.pixels
    iterations = 0
    while True:
        below, sum_below, above, sum_above = histogram.split(cutoff)
        if below == 0 or above == 0:
            break
        following = (sum_below * above + sum_above * below) // (2 * below * above)
        iterations += 1
        if following == cutoff:
            break
        cutoff = following
        if iterations == MAX_ISODATA_ITERATIONS:
            break
    return cutoff, iterations
