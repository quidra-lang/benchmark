from predicates import incircle, orient


def canonical(a, b, c):
    return min((a, b, c), (b, c, a), (c, a, b))


class Triangulation:
    def __init__(self, points):
        self.points = points
        self.directed = {}
        self.initial = (1, 2, 3) if orient(points[1], points[2], points[3]) > 0 else (1, 3, 2)
        self._add(*self.initial)

    def _add(self, a, b, c):
        self.directed[a, b] = c
        self.directed[b, c] = a
        self.directed[c, a] = b

    def _remove(self, a, b, c):
        del self.directed[a, b]
        del self.directed[b, c]
        del self.directed[c, a]

    def triangles(self):
        return sorted({canonical(a, b, c) for (a, b), c in self.directed.items()})

    def hull_edges(self):
        return sorted((u, v) for u, v in self.directed if (v, u) not in self.directed)

    def insert(self, s):
        points = self.points
        containing = None
        for a, b, c in self.triangles():
            if (orient(points[a], points[b], points[s]) > 0
                    and orient(points[b], points[c], points[s]) > 0
                    and orient(points[c], points[a], points[s]) > 0):
                containing = (a, b, c)
                break

        visible = 0
        if containing is not None:
            a, b, c = containing
            self._remove(a, b, c)
            check = {(a, b), (b, c), (c, a)}
            kind = "inside"
        else:
            check = {(v, u) for u, v in self.hull_edges()
                     if orient(points[u], points[v], points[s]) < 0}
            visible = len(check)
            kind = "outside"
        for a, b in check:
            self._add(a, b, s)

        flips = 0
        while check:
            a, b = check.pop()
            q = self.directed.get((b, a))
            if q is not None and incircle(points[a], points[b], points[s], points[q]) > 0:
                self._remove(a, b, s)
                self._remove(b, a, q)
                self._add(a, q, s)
                self._add(q, b, s)
                check.update(((a, q), (q, b)))
                flips += 1

        return {
            "kind": kind,
            "containing": containing,
            "visible": visible,
            "flips": flips,
            "triangle_count": len(self.directed) // 3,
            "hull_count": len(self.hull_edges()),
        }

    def visibility_walk(self, query, triangles, edge_triangles):
        path = [1]
        while True:
            a, b, c = triangles[path[-1]]
            for u, v in ((a, b), (b, c), (c, a)):
                if orient(self.points[u], self.points[v], query) < 0:
                    following = edge_triangles.get((v, u))
                    if following is None:
                        return path, tuple(sorted((u, v)))
                    path.append(following)
                    break
            else:
                return path, None
