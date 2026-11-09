WILDCARD = "*"


class Spec:
    def __init__(self, line, words):
        self.line = line
        self.pattern = words[0]
        section, _, self.key = self.pattern.rpartition(".")
        self.section_parts = section.split(".")
        self.wildcard = WILDCARD in self.section_parts
        self.kind = words[1]
        self.required = False
        self.secret = False
        self.unique = False
        self.fixed = False
        self.default = None
        self.range = None
        self.values = []
        self.item = "string"
        self.aliases = []
        self.when = None
        self.le = None
        for attribute in words[2:]:
            self.add_attribute(attribute)

    def add_attribute(self, attribute):
        name, _, argument = attribute.partition("=")
        if name == "required":
            self.required = True
        elif name == "secret":
            self.secret = True
        elif name == "unique":
            self.unique = True
        elif name == "fixed":
            self.fixed = True
        elif name == "default":
            self.default = argument
        elif name == "range":
            lower, _, upper = argument.partition("..")
            self.range = (lower, upper)
        elif name == "values":
            self.values = argument.split(",")
        elif name == "item":
            self.item = argument
        elif name == "alias":
            self.aliases = argument.split(",")
        elif name == "when":
            self.when = argument
        elif name == "le":
            self.le = argument

    def matches(self, section):
        parts = section.split(".")
        return len(parts) == len(self.section_parts) and all(
            pattern in (WILDCARD, part) for pattern, part in zip(self.section_parts, parts)
        )


class Schema:
    def __init__(self, specs):
        self.specs = specs
        self.exact = {spec.pattern: spec for spec in specs if not spec.wildcard}

    def spec_for(self, full_key):
        if full_key in self.exact:
            return self.exact[full_key]
        section, _, key = full_key.rpartition(".")
        for spec in self.specs:
            if spec.wildcard and spec.key == key and spec.matches(section):
                return spec
        return None

    def target_keys(self, spec, sections):
        if not spec.wildcard:
            return [spec.pattern]
        keys = []
        for section in sorted(sections):
            key = section + "." + spec.key
            if spec.matches(section) and self.spec_for(key) is spec:
                keys.append(key)
        return keys


def load_schema(path):
    with open(path) as handle:
        lines = handle.read().split("\n")[:-1]
    specs = []
    for number, line in enumerate(lines, 1):
        if line.strip(" ") != "" and not line.startswith("#"):
            specs.append(Spec(number, line.split(" ")))
    return Schema(specs)
