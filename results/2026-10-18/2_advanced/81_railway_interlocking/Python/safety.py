"""Count all prescribed safety checks and preserve violation record order."""

from collections import Counter


PROPERTIES = ("OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING")


class Safety:
    def __init__(self):
        self.checks, self.violations, self.records = Counter(), Counter(), []

    def check(self, time, kind, details=None):
        self.checks[kind] += 1
        if details is not None:
            self.violations[kind] += 1
            self.records.append(f"VIOLATION {time} {kind} {details}")

    def inspect(self, time, layout, routes):
        for section in layout.sections.values():
            details = section.name + " " + ",".join(section.occupants) if len(section.occupants) >= 2 else None
            self.check(time, "OCCUPANCY", details)
        for point in layout.points.values():
            if point.moving:
                details = None
                if layout.sections[point.common].occupants:
                    details = point.name + " occupied"
                elif any(routes[name].state in ("USED", "APPROACH") for name, _ in point.locks):
                    details = point.name + " locked"
                self.check(time, "POINT_MOTION", details)
        locked = [route for route in routes.values() if route.state in ("LOCKED", "APPROACH")]
        for index, first in enumerate(locked):
            for second in locked[index + 1:]:
                conflict = second.name in first.conflicts or first.name in second.conflicts
                self.check(time, "CONFLICT", first.name + " " + second.name if conflict else None)

    def report(self):
        lines = []
        for kind in PROPERTIES:
            verdict = "FAIL" if self.violations[kind] else "OK"
            lines.append(f"{kind} {verdict} checks {self.checks[kind]} violations {self.violations[kind]}")
        lines.extend(self.records)
        lines.append("RESULT " + ("UNSAFE" if self.records else "SAFE"))
        return lines
