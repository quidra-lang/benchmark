"""Read materials, camera, lights and objects from the scene file."""

from pathlib import Path

from vector3 import neg, norm


class Material:
    def __init__(self, name, values):
        self.name = name
        self.color = tuple(values[:3])
        self.kd, self.ks, self.n = values[3:6]
        self.kr, self.kt, self.ior = values[6:9]
        self.checker = None


class Scene:
    def __init__(self, path):
        self.materials = {}
        self.objects = []
        self.lights = []
        self.fog = None
        for line in Path(path).read_text(encoding="ascii").splitlines():
            if not line or line.startswith("#"):
                continue
            words = line.split()
            kind = words[0]
            if kind == "material":
                name = words[1]
                self.materials[name] = Material(name, list(map(int, words[2:])))
            elif kind == "checker":
                values = list(map(int, words[2:]))
                self.materials[words[1]].checker = (tuple(values[:3]), values[3])
            elif kind in ("sphere", "plane", "box"):
                self.read_object(kind, words)
            elif kind in ("point", "spot", "sun", "area"):
                self.read_light(kind, list(map(int, words[1:])))
            elif kind == "ambient":
                self.ambient = int(words[1])
            else:
                setattr(self, kind, tuple(map(int, words[1:])))

    def read_object(self, kind, words):
        values = list(map(int, words[3:]))
        obj = {
            "number": len(self.objects) + 1,
            "kind": kind,
            "label": words[1],
            "material": self.materials[words[2]],
        }
        if kind == "sphere":
            obj.update(center=tuple(values[:3]), radius=values[3])
        elif kind == "plane":
            obj.update(point=tuple(values[:3]), normal=norm(values[3:]))
        else:
            obj.update(lo=tuple(values[:3]), hi=tuple(values[3:]))
        self.objects.append(obj)

    def read_light(self, kind, values):
        light = {
            "number": len(self.lights) + 1,
            "kind": kind,
            "intensity": values[-1],
            "samples": 1,
        }
        if kind == "sun":
            light["direction"] = norm(neg(values[:3]))
        else:
            light["position"] = tuple(values[:3])
            if kind == "spot":
                light.update(direction=norm(values[3:6]),
                             outer=values[6], inner=values[7])
            elif kind == "area":
                light.update(u=tuple(values[3:6]), v=tuple(values[6:9]),
                             divisions=values[9], samples=values[9] ** 2)
        self.lights.append(light)
