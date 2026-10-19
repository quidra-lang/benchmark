"""BGP output notation and ASCII/LF report writing."""

from pathlib import Path

import policy


def path_text(path):
    return ",".join(map(str, path))


def attribute_text(attribute):
    return (f"path {path_text(attribute.path)} origin {attribute.origin} med {attribute.med} "
            f"comm {policy.communities_text(attribute.communities)}")


def route_text(route):
    if route is None:
        return "NONE"
    communities = policy.communities_text(route.communities)
    if route.local:
        return f"LOCAL origin {route.origin} comm {communities}"
    return (f"next {route.neighbor} path {path_text(route.path)} link {route.link.name} "
            f"lp {route.local_pref} med {route.med} origin {route.origin} comm {communities}")


def write_reports(reports):
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, lines in reports.items():
        (output / filename).write_text("".join(line + "\n" for line in lines),
                                       encoding="ascii", newline="\n")
