from fractions import Fraction


def dependency(counts, first, second):
    forward = counts[first, second]
    backward = counts[second, first]
    return Fraction(forward - backward, forward + backward + 1)


def loop_measure(count):
    return Fraction(count, count + 1)


def split_measure(counts, activity, first, second):
    numerator = counts[first, second] + counts[second, first]
    denominator = counts[activity, first] + counts[activity, second] + 1
    return Fraction(numerator, denominator)


def join_measure(counts, activity, first, second):
    numerator = counts[first, second] + counts[second, first]
    denominator = counts[first, activity] + counts[second, activity] + 1
    return Fraction(numerator, denominator)
