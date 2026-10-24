from ini_parser import is_section_name
from lexer import LITERAL_DOLLAR


class Expander:
    def __init__(self, values, origins):
        self.values = values
        self.origins = origins
        self.results = {}
        self.in_progress = []
        self.cycle_keys = set()
        self.diagnostics = []

    def report(self, origin, code, message):
        document, line = origin
        self.diagnostics.append((document, line, code, message))

    def expand(self, key):
        if key not in self.results:
            self.in_progress.append(key)
            result = self.evaluate(key)
            self.in_progress.pop()
            self.results[key] = result
        return self.results[key]

    def evaluate(self, key):
        value = self.values[key]
        origin = self.origins[key]
        section = key.rpartition(".")[0]
        pieces = []
        position = 0
        while position < len(value):
            if not value.startswith("${", position):
                char = value[position]
                pieces.append("$" if char == LITERAL_DOLLAR else char)
                position += 1
                continue
            close = value.find("}", position + 2)
            if close < 0 or not is_section_name(value[position + 2:close]):
                self.report(origin, "E_BAD_REF", f"{key}: invalid reference")
                return None
            reference = value[position + 2:close]
            target = reference if "." in reference else section + "." + reference
            if target not in self.values:
                self.report(origin, "E_UNDEFINED", f"{key}: undefined reference {target}")
                return None
            if target in self.in_progress:
                self.report_cycle(target)
                expanded = None
            else:
                expanded = self.expand(target)
            if expanded is None:
                if key not in self.cycle_keys:
                    self.report(origin, "E_DEPENDENCY", f"{key}: depends on failed key {target}")
                return None
            pieces.append(expanded)
            position = close + 1
        return "".join(pieces)

    def report_cycle(self, target):
        path = self.in_progress[self.in_progress.index(target):] + [target]
        self.report(self.origins[target], "E_CYCLE", "interpolation cycle " + " -> ".join(path))
        self.cycle_keys.update(path)
