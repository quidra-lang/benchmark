"""Immutable BGP attributes/routes and the staged best-route decision."""

from collections import namedtuple


Attribute = namedtuple("Attribute", "path origin med communities")


class Route(namedtuple("RouteValues", "path origin med communities local_pref link")):
    __slots__ = ()

    @property
    def local(self):
        return self.link is None

    @property
    def neighbor(self):
        return self.path[0]

    @classmethod
    def originated(cls, origin, communities):
        return cls((), origin, 0, communities, None, None)


def best_route(candidates, router_ids):
    remaining = list(candidates)
    if len(remaining) == 1:
        return remaining[0], "ONLY"
    origin_order = {"IGP": 0, "EGP": 1, "INCOMPLETE": 2}
    stages = (
        ("LOCALPREF", lambda route: -route.local_pref),
        ("ASPATH", lambda route: len(route.path)),
        ("ORIGIN", lambda route: origin_order[route.origin]),
        ("MED", None),
        ("ROUTERID", lambda route: router_ids[route.neighbor]),
        ("LINK", lambda route: route.link.number),
    )
    for reason, key in stages:
        if reason == "MED":
            minima = {}
            for route in remaining:
                minima[route.neighbor] = min(minima.get(route.neighbor, route.med), route.med)
            remaining = [route for route in remaining if route.med == minima[route.neighbor]]
        else:
            minimum = min(key(route) for route in remaining)
            remaining = [route for route in remaining if key(route) == minimum]
        if len(remaining) == 1:
            return remaining[0], reason
