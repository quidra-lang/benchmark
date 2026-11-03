"""Track objects and direction-dependent connections at section ends."""

from collections import Counter
from pathlib import Path
from types import SimpleNamespace


class Section:
    def __init__(self, name, length, row, first, last):
        self.name, self.length, self.row, self.first, self.last = name, length, row, first, last
        self.failed, self.occupants = False, []
        self.occupied_seconds, self.locked_seconds, self.trains = 0, 0, set()


class Point:
    def __init__(self, name, side, common, normal, reverse, row, column):
        self.name, self.side, self.common = name, side, common
        self.normal, self.reverse, self.row, self.column = normal, reverse, row, column
        self.position, self.moving, self.failed = "N", False, False
        self.target, self.completion = None, None
        self.throws, self.locked_seconds, self.moving_seconds = 0, 0, 0

    @property
    def detected(self):
        return not self.moving and not self.failed


class Layout:
    def __init__(self):
        self.sections, self.points, self.signals = {}, {}, {}
        self.buffers, self.boundaries, self.labels = {}, {}, []
        self.ends, self.signals_at = {}, {}
        for line in Path("input/layout.txt").read_text(encoding="ascii").splitlines():
            kind, *fields = line.split()
            if kind == "SECTION":
                item = Section(fields[0], *map(int, fields[1:]))
                self.sections[item.name] = item
            elif kind == "JOINT":
                first, second = fields
                self.ends[first, "R"] = "section", second
                self.ends[second, "L"] = "section", first
            elif kind == "POINT":
                item = Point(*fields[:5], *map(int, fields[5:]))
                self.points[item.name] = item
                self.ends[item.common, item.side] = "point", item.name
                other = "L" if item.side == "R" else "R"
                self.ends[item.normal, other] = self.ends[item.reverse, other] = "point", item.name
            elif kind == "SIGNAL":
                name, section, direction, row, column = fields
                item = SimpleNamespace(name=name, section=section, direction=direction, row=int(row),
                                       column=int(column), aspect="RED", seconds=Counter(), passes=0)
                self.signals[name] = self.signals_at[section, direction] = item
            elif kind in ("BUFFER", "BOUNDARY"):
                name, section, end = fields[:3]
                item = SimpleNamespace(name=name, section=section, end=end)
                if kind == "BUFFER":
                    item.row, item.column = map(int, fields[3:])
                    self.buffers[name] = item
                else:
                    self.boundaries[name] = item
                self.ends[section, end] = kind.lower(), name
            else:
                self.labels.append((int(fields[0]), int(fields[1]), fields[2]))

    def beyond(self, section, direction):
        kind, name = self.ends[section, "R" if direction == "UP" else "L"]
        if kind != "point":
            return kind, name
        point = self.points[name]
        branch = point.normal if point.position == "N" else point.reverse
        if point.moving or section != point.common and section != branch:
            return "impassable", None
        return "section", branch if section == point.common else point.common
