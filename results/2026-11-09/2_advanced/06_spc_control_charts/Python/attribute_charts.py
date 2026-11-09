from math import sqrt


ATTRIBUTE_CHARTS = ("p", "np", "c", "u")
COUNT_CHARTS = ("np", "c")


class CenterLine:
    def __init__(self, chart, lots):
        defectives = sum(lot.defectives for lot in lots)
        defects = sum(lot.defects for lot in lots)
        inspected = sum(lot.inspected for lot in lots)
        self.chart = chart
        self.fraction = defectives / inspected
        if chart == "p":
            self.value = defectives / inspected
        elif chart == "np":
            self.value = defectives / len(lots)
        elif chart == "c":
            self.value = defects / len(lots)
        else:
            self.value = defects / inspected


class LotPoint:
    def __init__(self, lot, center):
        cl = center.value
        if center.chart == "p":
            self.value = lot.defectives / lot.inspected
            sigma = sqrt(cl * (1 - cl) / lot.inspected)
        elif center.chart == "np":
            self.value = lot.defectives
            sigma = sqrt(cl * (1 - center.fraction))
        elif center.chart == "c":
            self.value = lot.defects
            sigma = sqrt(cl)
        else:
            self.value = lot.defects / lot.inspected
            sigma = sqrt(cl / lot.inspected)
        self.ucl = cl + 3 * sigma
        self.lcl = cl - 3 * sigma
        if self.lcl < 0:
            self.lcl = 0.0
        self.z = (self.value - cl) / sigma
        if self.value > self.ucl:
            self.status = "high"
        elif self.value < self.lcl:
            self.status = "low"
        else:
            self.status = "ok"
