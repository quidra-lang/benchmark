import bisect

from day_rules import POS_INFINITY


OFFSET_LIMIT = 57600


class Period:
    def __init__(self, start, offset, dst, abbreviation):
        self.start = start
        self.offset = offset
        self.dst = dst
        self.abbreviation = abbreviation

    def state(self):
        return self.offset, self.dst, self.abbreviation


class Timeline:
    def __init__(self, periods):
        self.periods = periods
        self.starts = [period.start for period in periods]

    def index_at(self, time):
        return bisect.bisect_right(self.starts, time) - 1

    def period_at(self, time):
        return self.periods[self.index_at(time)]

    def end_of(self, index):
        if index + 1 < len(self.periods):
            return self.starts[index + 1]
        return POS_INFINITY

    def nearby(self, first_local, last_local):
        first = self.index_at(first_local - OFFSET_LIMIT)
        last = self.index_at(last_local + OFFSET_LIMIT)
        return range(first, last + 1)

    def candidates(self, local):
        found = []
        for index in self.nearby(local, local):
            time = local - self.periods[index].offset
            if self.starts[index] <= time < self.end_of(index):
                found.append(index)
        return found

    def skipping_transition(self, local):
        for index in self.nearby(local, local):
            if index == 0:
                continue
            start = self.starts[index]
            if start + self.periods[index - 1].offset <= local < start + self.periods[index].offset:
                return index
        return None
