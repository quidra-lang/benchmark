"""Render a fixed-point scene and write images, accounting and query records."""

from pathlib import Path

from fixed_point import S, mul
from intersect import bounds, candidate, outward_normal, slab
from scene import Scene
from shading import base_color, mix, phong, reflected, refraction
from vector3 import add, dot, length, neg, norm, sc, sub


RAY_KINDS = ("primary", "reflection", "refraction", "shadow")
LIGHT_COUNTS = ("pixels", "shadow_rays", "blocked", "attenuated",
                "backfacing", "outside")
BLACK = (0, 0, 0)


def vector_text(vector):
    return " ".join(map(str, vector))


def write_lines(path, lines):
    text = "\n".join(lines)
    Path(path).write_text(text + "\n" if lines else "", encoding="ascii", newline="\n")


def read_settings(path):
    settings = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        key, *values = line.split()
        settings[key] = tuple(map(int, values))
    return settings


def union_box(objects):
    lo = tuple(min(obj["bounds"][0][a] for obj in objects) for a in range(3))
    hi = tuple(max(obj["bounds"][1][a] for obj in objects) for a in range(3))
    return lo, hi


def surface_cost(objects):
    lo, hi = union_box(objects)
    dx, dy, dz = sub(hi, lo)
    return (dx * dy + dy * dz + dz * dx) * len(objects)


class Renderer:
    def __init__(self, scene, settings):
        self.scene = scene
        self.width, self.height = settings["size"]
        self.contrast = settings["contrast"][0]
        self.max_depth = settings["depth"][0]
        self.far = settings["far"][0]
        self.epsilon = settings["epsilon"][0]
        margin = settings["pad"][0]
        self.objects = scene.objects
        self.lights = scene.lights
        self.planes = [obj for obj in self.objects if obj["kind"] == "plane"]
        self.nodes = []
        bounded = []
        for obj in self.objects:
            obj["bounds"] = bounds(obj, margin)
            obj["leaf_depth"] = None
            if obj["bounds"] is not None:
                bounded.append(obj)
        self.root = self.build_bvh(bounded, 0) if bounded else None
        self.rays = dict.fromkeys(RAY_KINDS, 0)
        self.misses = dict.fromkeys(RAY_KINDS[:3], 0)
        self.depth_counts = [0] * (self.max_depth + 1)
        self.tests = {kind: {"nodes": 0, "objects": 0} for kind in RAY_KINDS}
        self.object_counts = [dict.fromkeys(("primary", "secondary", "shadow"), 0)
                              for _ in self.objects]
        self.light_counts = [dict.fromkeys(LIGHT_COUNTS, 0) for _ in self.lights]
        self.total_internal_reflections = 0
        self.clamped = 0
        self.supersampled = 0
        self.pixels = []

    def build_bvh(self, objects, depth):
        node = {"bounds": union_box(objects), "depth": depth, "visits": 0,
                "objects": None, "left": None, "right": None}
        self.nodes.append(node)
        if len(objects) <= 2:
            node["objects"] = sorted(objects, key=lambda obj: obj["number"])
            for obj in objects:
                obj["leaf_depth"] = depth
            return node
        best_key = None
        best_groups = None
        for axis in range(3):
            ordered = sorted(objects, key=lambda obj: (
                (obj["bounds"][0][axis] + obj["bounds"][1][axis]) // 2,
                obj["number"]))
            for split in range(1, len(ordered)):
                left, right = ordered[:split], ordered[split:]
                key = (surface_cost(left) + surface_cost(right), axis, split)
                if best_key is None or key < best_key:
                    best_key = key
                    best_groups = left, right
        left, right = best_groups
        node["left"] = self.build_bvh(left, depth + 1)
        node["right"] = self.build_bvh(right, depth + 1)
        return node

    def test_node(self, node, origin, direction, kind, counted):
        if counted:
            self.tests[kind]["nodes"] += 1
            node["visits"] += 1
        lo, hi = node["bounds"]
        interval = slab(lo, hi, origin, direction)
        if interval is None or interval[2] <= self.epsilon:
            return None
        return interval[0]

    def test_object(self, obj, origin, direction, kind, counted):
        if counted:
            self.tests[kind]["objects"] += 1
        return candidate(obj, origin, direction, self.epsilon)

    def nearest(self, origin, direction, kind="primary", counted=False):
        best = None

        def consider(obj):
            nonlocal best
            hit = self.test_object(obj, origin, direction, kind, counted)
            if hit is None or hit[0] > self.far:
                return
            if best is None or (hit[0], obj["number"]) < (best[1][0], best[0]["number"]):
                best = obj, hit

        def visit(node):
            entry = self.test_node(node, origin, direction, kind, counted)
            if entry is None or entry > self.far:
                return
            if best is not None and entry > best[1][0]:
                return
            if node["objects"] is not None:
                for obj in node["objects"]:
                    consider(obj)
            else:
                visit(node["left"])
                visit(node["right"])

        for obj in self.planes:
            consider(obj)
        if self.root is not None:
            visit(self.root)
        return best

    def occluders(self, origin, direction, distance, counted=False):
        found = []

        def consider(obj):
            hit = self.test_object(obj, origin, direction, "shadow", counted)
            if hit is not None and hit[0] < distance:
                found.append(obj)
                if counted:
                    self.object_counts[obj["number"] - 1]["shadow"] += 1

        def visit(node):
            entry = self.test_node(node, origin, direction, "shadow", counted)
            if entry is None or entry >= distance:
                return
            if node["objects"] is not None:
                for obj in node["objects"]:
                    consider(obj)
            else:
                visit(node["left"])
                visit(node["right"])

        for obj in self.planes:
            consider(obj)
        if self.root is not None:
            visit(self.root)
        return sorted(found, key=lambda obj: obj["number"])

    def camera_ray(self, qx, qy):
        hw, hh = self.scene.view
        u = (qx - 2 * self.width) * hw // (2 * self.width)
        v = (2 * self.height - qy) * hh // (2 * self.height)
        direction = add(add(self.scene.forward, sc(self.scene.right, u)),
                        sc(self.scene.up, v))
        return self.scene.eye, norm(direction)

    def intersection_info(self, nearest, origin, direction):
        obj, intersection = nearest
        distance = intersection[0]
        point = add(origin, sc(direction, distance))
        outward = outward_normal(obj, point, direction, intersection)
        front = dot(outward, direction) <= 0
        normal = outward if front else neg(outward)
        return {"object": obj, "distance": distance, "point": point,
                "normal": normal, "front": front,
                "base": base_color(obj["material"], point)}

    def light_samples(self, light, point):
        if light["kind"] == "sun":
            return [(light["direction"], self.far, light["intensity"])]
        positions = []
        if light["kind"] == "area":
            k = light["divisions"]
            for j in range(k):
                for i in range(k):
                    position = tuple(light["position"][a]
                                     + (2 * i + 1) * light["u"][a] // (2 * k)
                                     + (2 * j + 1) * light["v"][a] // (2 * k)
                                     for a in range(3))
                    positions.append(position)
        else:
            positions.append(light["position"])
        intensity = light["intensity"] // light["samples"]
        samples = []
        for position in positions:
            relative = sub(position, point)
            samples.append((norm(relative), length(relative), intensity))
        return samples

    def cone_factor(self, light, direction):
        if light["kind"] != "spot":
            return S
        cosine = -dot(direction, light["direction"])
        if cosine <= light["outer"]:
            return 0
        if cosine >= light["inner"]:
            return S
        return (cosine - light["outer"]) * S // (light["inner"] - light["outer"])

    def sample_contribution(self, light, sample, info, view, pixel):
        direction, distance, intensity = sample
        ndl = dot(info["normal"], direction)
        counters = self.light_counts[light["number"] - 1]
        if ndl <= 0:
            if pixel is not None:
                counters["backfacing"] += 1
            return 0, 0, 0
        factor = self.cone_factor(light, direction)
        if factor == 0:
            if pixel is not None:
                counters["outside"] += 1
            return 0, 0, 0
        if pixel is not None:
            self.rays["shadow"] += 1
            pixel["rays"] += 1
            counters["shadow_rays"] += 1
        occluders = self.occluders(info["point"], direction, distance, pixel is not None)
        for obj in occluders:
            factor = mul(factor, obj["material"].kt)
        if factor == 0:
            if pixel is not None:
                counters["blocked"] += 1
            return 0, 0, 0
        if occluders and pixel is not None:
            counters["attenuated"] += 1
        diffuse, specular = phong(info["object"]["material"], info["normal"],
                                  direction, view, ndl, intensity, factor)
        return 1, diffuse, specular

    def local_color(self, info, direction, pixel):
        lighting = []
        view = neg(direction)
        for light in self.lights:
            lit = diffuse = specular = 0
            for sample in self.light_samples(light, info["point"]):
                count, dif, spe = self.sample_contribution(light, sample, info, view, pixel)
                lit += count
                diffuse += dif
                specular += spe
            lighting.append((lit, diffuse, specular))
        diffuse_sum = sum(item[1] for item in lighting)
        specular_sum = sum(item[2] for item in lighting)
        raw = tuple(c * (self.scene.ambient + diffuse_sum) // S
                    + 255 * specular_sum // S for c in info["base"])
        if pixel is not None:
            self.clamped += sum(c > 255 for c in raw)
        info["lighting"] = lighting
        info["illumination"] = sum(item[0] > 0 for item in lighting)
        return tuple(min(c, 255) for c in raw)

    def apply_fog(self, color, distance):
        if self.scene.fog is None:
            return color
        r, g, b, start, end = self.scene.fog
        if distance <= start:
            factor = 0
        elif distance >= end:
            factor = S
        else:
            factor = (distance - start) * S // (end - start)
        return mix((color, S - factor), ((r, g, b), factor))

    def trace(self, origin, direction, kind="primary", depth=0, pixel=None, record=None):
        if pixel is not None:
            self.rays[kind] += 1
            self.depth_counts[depth] += 1
            pixel["rays"] += 1
            pixel["depth"] = max(pixel["depth"], depth)
        if record is not None:
            record.append(f"ray {kind} {depth} origin {vector_text(origin)} "
                          f"direction {vector_text(direction)}")
        nearest = self.nearest(origin, direction, kind, pixel is not None)
        if nearest is None:
            if pixel is not None:
                self.misses[kind] += 1
            color = self.scene.background
            if record is not None:
                record.extend(("miss", f"color {vector_text(color)}"))
            return {"color": color, "hit": None}
        info = self.intersection_info(nearest, origin, direction)
        obj = info["object"]
        if pixel is not None:
            category = "primary" if kind == "primary" else "secondary"
            self.object_counts[obj["number"] - 1][category] += 1
        local = self.local_color(info, direction, pixel)
        if record is not None:
            record.append(f"hit {obj['label']} t {info['distance']} "
                          f"point {vector_text(info['point'])} normal {vector_text(info['normal'])} "
                          f"base {vector_text(info['base'])}")
            for light, (lit, diffuse, specular) in zip(self.lights, info["lighting"]):
                record.append(f"light {light['number']} lit {lit} of {light['samples']} "
                              f"diffuse {diffuse} specular {specular}")
            record.append(f"local {vector_text(local)}")
        material = obj["material"]
        color = local
        if depth < self.max_depth and (material.kr > 0 or material.kt > 0):
            wr, wt, transmitted, internal = refraction(material, direction,
                                                       info["normal"], info["front"])
            if internal:
                if pixel is not None:
                    self.total_internal_reflections += 1
                if record is not None:
                    record.append("total_internal_reflection")
            local_weight = S - material.kr - material.kt
            if record is not None:
                record.append(f"weights {local_weight} {wr} {wt}")
            reflected_color = refracted_color = BLACK
            if wr > 0:
                reflected_color = self.trace(info["point"], reflected(direction, info["normal"]),
                                             "reflection", depth + 1, pixel, record)["color"]
            if wt > 0:
                refracted_color = self.trace(info["point"], transmitted, "refraction",
                                             depth + 1, pixel, record)["color"]
            color = mix((local, local_weight), (reflected_color, wr), (refracted_color, wt))
        color = self.apply_fog(color, info["distance"])
        if record is not None:
            record.append(f"color {vector_text(color)}")
        return {"color": color, "hit": info}

    def render(self):
        for y in range(self.height):
            for x in range(self.width):
                pixel = {"x": x, "y": y, "rays": 0, "depth": 0, "samples": 1, "label": "."}
                origin, direction = self.camera_ray(4 * x + 2, 4 * y + 2)
                result = self.trace(origin, direction, pixel=pixel)
                pixel["center"] = pixel["color"] = result["color"]
                pixel["hit"] = result["hit"]
                if result["hit"] is not None:
                    pixel["label"] = result["hit"]["object"]["label"]
                    for counters, lighting in zip(self.light_counts, result["hit"]["lighting"]):
                        if lighting[0] > 0:
                            counters["pixels"] += 1
                self.pixels.append(pixel)
        for pixel in self.pixels:
            x, y = pixel["x"], pixel["y"]
            adjacent = []
            for nx, ny in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)):
                if 0 <= nx < self.width and 0 <= ny < self.height:
                    adjacent.append(self.pixels[ny * self.width + nx])
            boundary = any(other["label"] != pixel["label"] or
                           max(abs(a - b) for a, b in zip(other["center"], pixel["center"]))
                           > self.contrast for other in adjacent)
            if not boundary:
                continue
            self.supersampled += 1
            pixel["samples"] = 4
            colors = []
            for dx, dy in ((1, 1), (3, 1), (1, 3), (3, 3)):
                origin, direction = self.camera_ray(4 * x + dx, 4 * y + dy)
                colors.append(self.trace(origin, direction, pixel=pixel)["color"])
            pixel["color"] = tuple(sum(color[a] for color in colors) // 4 for a in range(3))

    def write_netpbm(self, path, magic, values):
        lines = [magic, f"{self.width} {self.height}", "255"]
        for y in range(self.height):
            row = values[y * self.width:(y + 1) * self.width]
            if magic == "P3":
                lines.append(" ".join(vector_text(color) for color in row))
            else:
                lines.append(" ".join(map(str, row)))
        write_lines(path, lines)

    def write_map(self, path, values):
        lines = ["".join(values[y * self.width:(y + 1) * self.width])
                 for y in range(self.height)]
        write_lines(path, lines)

    def distance_range(self):
        distances = [pixel["hit"]["distance"] for pixel in self.pixels if pixel["hit"] is not None]
        return (min(distances), max(distances)) if distances else None

    def mean_color(self, pixels):
        return tuple(sum(pixel["color"][a] for pixel in pixels) // len(pixels) for a in range(3))

    def write_images(self, folder):
        distance_range = self.distance_range()
        max_cost = max(pixel["rays"] for pixel in self.pixels)
        depth_values = []
        normal_values = []
        albedo_values = []
        light_values = []
        for pixel in self.pixels:
            hit = pixel["hit"]
            if hit is None:
                depth_values.append(0)
                normal_values.append(BLACK)
                albedo_values.append(BLACK)
                light_values.append(".")
                continue
            minimum, maximum = distance_range
            depth = 255 if minimum == maximum else 255 - 235 * (hit["distance"] - minimum) // (maximum - minimum)
            depth_values.append(depth)
            normal_values.append(tuple(max(0, min(255, (a + S) * 255 // (2 * S)))
                                       for a in hit["normal"]))
            albedo_values.append(hit["base"])
            light_values.append(str(hit["illumination"]))
        self.write_netpbm(folder / "image.ppm", "P3", [p["color"] for p in self.pixels])
        self.write_netpbm(folder / "depth.pgm", "P2", depth_values)
        self.write_netpbm(folder / "normal.ppm", "P3", normal_values)
        self.write_netpbm(folder / "albedo.ppm", "P3", albedo_values)
        self.write_netpbm(folder / "cost.pgm", "P2", [255 * p["rays"] // max_cost for p in self.pixels])
        self.write_map(folder / "object_map.txt", [p["label"] for p in self.pixels])
        self.write_map(folder / "light_map.txt", light_values)
        self.write_map(folder / "ray_depth.txt", [str(p["depth"]) for p in self.pixels])

    def node_lines(self):
        lines = []
        for node in self.nodes:
            lo, hi = node["bounds"]
            if node["objects"] is None:
                role = "inner"
            else:
                labels = "".join(obj["label"] for obj in node["objects"])
                role = f"leaf {labels}"
            lines.append(f"node {node['depth']} {role} box {vector_text(lo)} {vector_text(hi)} "
                         f"visits {node['visits']}")
        return lines

    def object_lines(self):
        lines = []
        for obj, counters in zip(self.objects, self.object_counts):
            pixels = [p for p in self.pixels if p["label"] == obj["label"]]
            if pixels:
                box = (min(p["x"] for p in pixels), min(p["y"] for p in pixels),
                       max(p["x"] for p in pixels), max(p["y"] for p in pixels))
                box_text = vector_text(box)
                color_text = vector_text(self.mean_color(pixels))
            else:
                box_text = color_text = "none"
            lines.append(f"object {obj['label']} {obj['kind']} primary {counters['primary']} "
                         f"secondary {counters['secondary']} shadow {counters['shadow']} "
                         f"pixels {len(pixels)} box {box_text} color {color_text}")
        return lines

    def statistics(self):
        lines = [f"image {self.width} {self.height}", f"supersampled {self.supersampled}"]
        ray_counts = " ".join(f"{kind} {self.rays[kind]}" for kind in RAY_KINDS)
        lines.append(f"rays {ray_counts} total {sum(self.rays.values())}")
        lines.append("misses " + " ".join(f"{kind} {self.misses[kind]}" for kind in RAY_KINDS[:3]))
        lines.append("depth " + vector_text(self.depth_counts))
        for kind in RAY_KINDS:
            counters = self.tests[kind]
            lines.append(f"tests {kind} nodes {counters['nodes']} objects {counters['objects']}")
        lines.append(f"total_internal_reflection {self.total_internal_reflections}")
        lines.append(f"clamped {self.clamped}")
        distances = self.distance_range()
        lines.append("distance " + (vector_text(distances) if distances is not None else "none"))
        lines.append(f"max_pixel_rays {max(p['rays'] for p in self.pixels)}")
        lines.append("mean " + vector_text(self.mean_color(self.pixels)))
        histogram = [0] * 8
        for pixel in self.pixels:
            r, g, b = pixel["color"]
            brightness = (299 * r + 587 * g + 114 * b) // 1000
            histogram[brightness // 32] += 1
        lines.append("histogram " + vector_text(histogram))
        lines.extend(self.node_lines())
        lines.extend(self.object_lines())
        for light, counters in zip(self.lights, self.light_counts):
            values = " ".join(f"{name} {counters[name]}" for name in LIGHT_COUNTS)
            lines.append(f"light {light['number']} {light['kind']} samples {light['samples']} {values}")
        return lines

    def pixel_query(self, x, y):
        pixel = self.pixels[y * self.width + x]
        distance = pixel["hit"]["distance"] if pixel["hit"] is not None else "none"
        return [f"label {pixel['label']} distance {distance} color {vector_text(pixel['color'])} "
                f"samples {pixel['samples']} rays {pixel['rays']}"]

    def object_query(self, label):
        obj = next(obj for obj in self.objects if obj["label"] == label)
        prefix = f"{obj['kind']} material {obj['material'].name}"
        if obj["bounds"] is None:
            return [prefix + " bounds none leaf none"]
        lo, hi = obj["bounds"]
        return [f"{prefix} bounds {vector_text(lo)} {vector_text(hi)} leaf {obj['leaf_depth']}"]

    def visible_query(self, point):
        relative = sub(point, self.scene.eye)
        direction = norm(relative)
        occluders = self.occluders(self.scene.eye, direction, length(relative) - self.epsilon)
        visibility = "no" if occluders else "yes"
        first = self.nearest(self.scene.eye, direction)
        if first is None:
            return [f"{visibility} first none"]
        obj, intersection = first
        return [f"{visibility} first {obj['label']} t {intersection[0]}"]

    def shadow_query(self, point):
        lines = []
        for light in self.lights:
            total_factor = 0
            numbers = set()
            for direction, distance, _ in self.light_samples(light, point):
                factor = self.cone_factor(light, direction)
                for obj in self.occluders(point, direction, distance):
                    numbers.add(obj["number"])
                    factor = mul(factor, obj["material"].kt)
                total_factor += factor
            labels = "".join(obj["label"] for obj in self.objects if obj["number"] in numbers)
            lines.append(f"light {light['number']} factor {total_factor} occluders {labels or 'none'}")
        return lines

    def region_query(self, x0, y0, x1, y1):
        pixels = [self.pixels[y * self.width + x]
                  for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        lines = [f"pixels {len(pixels)} mean {vector_text(self.mean_color(pixels))}"]
        for label in [obj["label"] for obj in self.objects] + ["."]:
            count = sum(pixel["label"] == label for pixel in pixels)
            if count:
                lines.append(f"label {label} {count}")
        return lines

    def queries(self, path):
        lines = []
        for number, line in enumerate(Path(path).read_text(encoding="ascii").splitlines(), 1):
            lines.append(f"query {number} {line}")
            kind, *arguments = line.split()
            if kind == "object":
                lines.extend(self.object_query(arguments[0]))
                continue
            values = tuple(map(int, arguments))
            if kind == "pixel":
                lines.extend(self.pixel_query(*values))
            elif kind == "trace":
                x, y = values
                origin, direction = self.camera_ray(4 * x + 2, 4 * y + 2)
                self.trace(origin, direction, record=lines)
            elif kind == "ray":
                self.trace(values[:3], norm(values[3:]), record=lines)
            elif kind == "visible":
                lines.extend(self.visible_query(values))
            elif kind == "shadow":
                lines.extend(self.shadow_query(values))
            elif kind == "region":
                lines.extend(self.region_query(*values))
        return lines


def main():
    scene = Scene(Path("input") / "scene.txt")
    renderer = Renderer(scene, read_settings(Path("input") / "render.txt"))
    renderer.render()
    output = Path("output")
    output.mkdir(parents=True, exist_ok=True)
    renderer.write_images(output)
    write_lines(output / "stats.txt", renderer.statistics())
    write_lines(output / "queries.txt", renderer.queries(Path("input") / "queries.txt"))


if __name__ == "__main__":
    main()
