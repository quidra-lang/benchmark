class Resolution:
    def __init__(self, name, entries, script=False):
        self.name = name
        self.entries = entries
        self.strong = [entry for entry in entries if entry.kind == "defined" and entry.binding == "global"]
        self.weak = [entry for entry in entries if entry.kind == "defined" and entry.binding == "weak"]
        self.commons = [entry for entry in entries if entry.kind == "common"]
        self.references = [entry for entry in entries if entry.kind == "undefined"]
        self.referrers = list(dict.fromkeys(entry.owner.name for entry in self.references))
        self.strong_definers = (["*script*"] if script else []) + [entry.owner.name for entry in self.strong]
        self.definition = None
        self.size = 0
        self.alignment = 1
        self.address = None
        self.live = False
        self.unresolved_referrers = []
        if script:
            self.kind = "script"
            self.definer = "*script*"
        elif self.strong:
            self.kind = "global"
            self.definition = self.strong[0]
            self.definer = self.definition.owner.name
        elif self.commons:
            self.kind = "common"
            self.size = max(entry.size for entry in self.commons)
            self.alignment = max(entry.alignment for entry in self.commons)
            self.definer = next(entry.owner.name for entry in self.commons if entry.size == self.size)
        elif self.weak:
            self.kind = "weak"
            self.definition = self.weak[0]
            self.definer = self.definition.owner.name
        elif any(entry.binding == "global" for entry in self.references):
            self.kind = "undefined"
            self.definer = "-"
        else:
            self.kind = "weakundef"
            self.definer = "-"


def resolve_names(entries, script_names):
    names = sorted(set(entries) | set(script_names))
    return {name: Resolution(name, entries.get(name, []), name in script_names) for name in names}
