from object_parser import parse_object, read_lines


class Member:
    def __init__(self, object_, exports):
        self.object = object_
        self.exports = exports
        self.loaded = False


def read_archive(path):
    lines = read_lines(path)
    members = []
    index = 0
    while index < len(lines):
        header = lines[index].split(" ")
        name = path.name + "(" + header[1] + ")"
        object_, index = parse_object(lines, index + 1, name)
        members.append(Member(object_, header[2:]))
    return members


def scan(members, is_undefined, extract):
    extracted = 0
    while True:
        changed = False
        for member in members:
            if member.loaded:
                continue
            reason = next((name for name in member.exports if is_undefined(name)), None)
            if reason is None:
                continue
            member.loaded = True
            extract(member.object, reason)
            extracted += 1
            changed = True
        if not changed:
            return extracted
