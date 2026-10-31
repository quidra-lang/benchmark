"""Read the benchmark OBJ subset and serialize repaired triangles."""

import re
from pathlib import Path


INTEGER = re.compile(r"-?[0-9]+\Z")
IGNORED = {"vt", "vn", "s", "o", "usemtl", "mtllib"}


def integer_word(word):
    return INTEGER.fullmatch(word) is not None


def read_obj(path="input/model.obj"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    vertices = [None]       # OBJ vertex numbers are one-based.
    polygons = []
    errors = []
    ignored = 0
    group = "default"
    for lineno, text in enumerate(lines, 1):
        if not text or text.startswith("#"):
            continue
        words = text.split(" ")
        command, args = words[0], words[1:]
        if command == "v":
            if len(args) != 3 or not all(integer_word(word) for word in args):
                errors.append((lineno, "bad_vertex"))
            else:
                vertices.append(tuple(map(int, args)))
        elif command == "f":
            if len(args) < 3:
                errors.append((lineno, "short_face"))
                continue
            resolved = []
            error = None
            for argument in args:
                vertex_part = argument.split("/", 1)[0]
                if not integer_word(vertex_part) or int(vertex_part) == 0:
                    error = "bad_index"
                    break
                number = int(vertex_part)
                if number < 0:
                    number = len(vertices) + number
                if not 1 <= number < len(vertices):
                    error = "out_of_range"
                    break
                resolved.append(number)
            if error:
                errors.append((lineno, error))
            else:
                polygons.append({
                    "number": len(polygons) + 1, "line": lineno,
                    "group": group, "vertices": tuple(resolved),
                })
        elif command == "g":
            group = args[0] if args else "default"
        elif command in IGNORED:
            ignored += 1
        else:
            errors.append((lineno, "unknown_keyword"))
    return {
        "lines": len(lines), "vertices": vertices,
        "polygons": polygons, "errors": errors, "ignored": ignored,
    }


def write_repaired_obj(vertices, faces):
    result = [
        f"# vertices {len(vertices) - 1} faces {len(faces)}"
    ]
    for point in vertices[1:]:
        result.append("v " + " ".join(map(str, point)))
    previous_group = None
    for face in faces:
        if face["group"] != previous_group:
            result.append("g " + face["group"])
            previous_group = face["group"]
        result.append("f " + " ".join(map(str, face["vertices"])))
    return result
