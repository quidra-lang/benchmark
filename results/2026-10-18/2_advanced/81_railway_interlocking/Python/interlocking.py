"""Route definitions and section, overlap and point lock operations."""

from pathlib import Path


def names(text):
    return [] if text == "-" else text.split(",")


class Route:
    def __init__(self, fields, layout):
        self.name, self.start, self.finish = fields[:3]
        self.points = [tuple(item.split(":")) for item in names(fields[3])]
        self.sections, self.overlap = names(fields[4]), names(fields[5])
        self.flank = [tuple(item.split(":")) for item in names(fields[6])]
        self.conflicts, self.approach_time = names(fields[7]), int(fields[8])
        self.direction = layout.signals[self.start].direction
        self.state, self.release_time = None, None
        self.passed, self.overlap_locked, self.overlap_counter = set(), False, 0
        self.requests, self.grants, self.uses, self.cancels = 0, 0, 0, 0
        self.wait, self.maxwait, self.locked_seconds = 0, 0, 0

    @property
    def requirements(self):
        return self.points + self.flank


class Interlocking:
    def __init__(self, layout):
        self.layout, self.routes = layout, {}
        for section in layout.sections.values():
            section.route_lock, section.overlap_locks = None, set()
        for point in layout.points.values():
            point.locks = set()
        for line in Path("input/routes.txt").read_text(encoding="ascii").splitlines():
            route = Route(line.split()[1:], layout)
            self.routes[route.name] = route

    def lock(self, route):
        route.state, route.release_time = "LOCKED", None
        route.passed, route.overlap_locked, route.overlap_counter = set(), True, 0
        for name in route.sections:
            self.layout.sections[name].route_lock = route.name
        for name in route.overlap:
            self.layout.sections[name].overlap_locks.add(route.name)
        for name, position in route.requirements:
            self.layout.points[name].locks.add((route.name, position))

    def unlock_points(self, route, sections=None):
        for point in self.layout.points.values():
            if sections is None or point.common in sections:
                point.locks = {lock for lock in point.locks if lock[0] != route.name}

    def unlock_section(self, route, name):
        section = self.layout.sections[name]
        if section.route_lock == route.name:
            section.route_lock = None
        self.unlock_points(route, {name})

    def unlock_overlap(self, route):
        for name in route.overlap:
            self.layout.sections[name].overlap_locks.discard(route.name)
        self.unlock_points(route, set(route.overlap))
        route.overlap_locked = False

    def release(self, route):
        for name in route.sections:
            if self.layout.sections[name].route_lock == route.name:
                self.layout.sections[name].route_lock = None
        if route.overlap_locked:
            self.unlock_overlap(route)
        self.unlock_points(route)
        route.state, route.release_time = None, None
