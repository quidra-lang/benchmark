"""Simultaneously decide signal clearance and its resulting aspect."""


def aspects(interlocking, occupied):
    layout, cleared = interlocking.layout, {}
    for signal in layout.signals.values():
        cleared[signal.name] = None
        for route in interlocking.routes.values():
            if route.start != signal.name or route.state != "LOCKED":
                continue
            if not all(layout.points[name].detected and layout.points[name].position == position
                       for name, position in route.requirements):
                continue
            if not any(occupied(name) for name in route.sections + route.overlap):
                cleared[signal.name] = route
                break
    result = []
    for signal in layout.signals.values():
        route = cleared[signal.name]
        if route is None:
            aspect = "RED"
        elif route.finish in layout.signals:
            aspect = "GREEN" if cleared[route.finish] is not None else "YELLOW"
        elif route.finish in layout.buffers:
            aspect = "YELLOW"
        else:
            aspect = "GREEN"
        result.append((signal, aspect))
    return result
