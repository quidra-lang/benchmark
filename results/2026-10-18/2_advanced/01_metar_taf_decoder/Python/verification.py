from units import hour_mark


CATEGORIES = ("VFR", "MVFR", "IFR", "LIFR")


def covers(forecast, time):
    hour = hour_mark(time)
    return forecast.issue <= time and forecast.start <= hour < forecast.end


def chosen_forecast(forecasts, time):
    chosen = None
    for forecast in forecasts:
        if covers(forecast, time) and (chosen is None or forecast.issue >= chosen.issue):
            chosen = forecast
    return chosen


class Contingency:
    def __init__(self):
        self.table = [[0] * len(CATEGORIES) for _ in CATEGORIES]
        self.temporary_hits = 0

    def add(self, forecast, observed, temporary_hit):
        self.table[CATEGORIES.index(forecast)][CATEGORIES.index(observed)] += 1
        if temporary_hit:
            self.temporary_hits += 1

    def row_total(self, row):
        return sum(self.table[row])

    def column_total(self, column):
        return sum(row[column] for row in self.table)

    def total(self):
        return sum(sum(row) for row in self.table)

    def hits(self):
        return sum(self.table[index][index] for index in range(len(CATEGORIES))), self.total()

    def hits_with_temporary(self):
        return self.temporary_hits, self.total()

    def skill_score(self):
        hits, total = self.hits()
        expected = sum(
            self.row_total(index) * self.column_total(index) for index in range(len(CATEGORIES))
        )
        return total * hits - expected, total * total - expected

    def detection(self, index):
        return self.table[index][index], self.column_total(index)

    def false_alarm(self, index):
        row_total = self.row_total(index)
        return row_total - self.table[index][index], row_total
