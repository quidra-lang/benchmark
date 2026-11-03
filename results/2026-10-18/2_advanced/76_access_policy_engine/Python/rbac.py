"""Ordered RBAC validation, role closure, SSD constraints and assignments."""

from pathlib import Path


class RBAC:
    def __init__(self, path="input/rbac.txt"):
        self.roles, self.inherits, self.permissions = set(), {}, {}
        self.ssd, self.dsd, self.assignments, self.diagnostics = [], [], [], []
        self.grants = set()
        lines = [(number, line.split()) for number, line in enumerate(Path(path).read_text(encoding="ascii").splitlines(), 1)]
        for keyword in ("ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"):
            for number, fields in lines:
                if fields[0] == keyword:
                    error = self.accept(keyword, fields[1:])
                    if error is not None:
                        self.diagnostics.append((number, keyword, error))
        self.diagnostics.sort()

    def closure(self, roles):
        reached, pending = set(roles), list(roles)
        while pending:
            for junior in self.inherits[pending.pop()]:
                if junior not in reached:
                    reached.add(junior)
                    pending.append(junior)
        return reached

    def path(self, start, finish):
        failed = set()

        def visit(role):
            if role == finish:
                return [role]
            if role not in failed:
                for junior in sorted(self.inherits[role]):
                    suffix = visit(junior)
                    if suffix is not None:
                        return [role] + suffix
                failed.add(role)
            return None

        return visit(start)

    def assigned(self, user, day):
        return {role for owner, role, first, last in self.assignments if owner == user and first <= day <= last}

    def authorized(self, user, day):
        return self.closure(self.assigned(user, day))

    def accept(self, keyword, fields):
        if keyword == "ROLE":
            role = fields[0]
            if role in self.roles:
                return "duplicate role " + role
            self.roles.add(role)
            self.inherits[role], self.permissions[role] = set(), set()
        elif keyword == "INHERITS":
            senior, junior = fields
            for role in (senior, junior):
                if role not in self.roles:
                    return "unknown role " + role
            if junior in self.inherits[senior]:
                return f"duplicate inheritance {senior} {junior}"
            if senior in self.closure([junior]):
                return "cycle " + " > ".join([senior] + self.path(junior, senior))
            self.inherits[senior].add(junior)
        elif keyword == "PERMIT":
            role, action, resource_type = fields
            if role not in self.roles:
                return "unknown role " + role
            if (action, resource_type) in self.permissions[role]:
                return f"duplicate permission {role} {action} {resource_type}"
            self.permissions[role].add((action, resource_type))
            self.grants.add((role, action, resource_type))
        elif keyword in ("SSD", "DSD"):
            name, cardinality, role_list = fields
            constraints = self.ssd if keyword == "SSD" else self.dsd
            if any(item[0] == name for item in constraints):
                return "duplicate constraint " + name
            roles = role_list.split(",")
            for role in roles:
                if role not in self.roles:
                    return "unknown role " + role
            cardinality = int(cardinality)
            if not 2 <= cardinality <= len(roles):
                return f"bad cardinality {name} {cardinality}"
            constraints.append((name, cardinality, set(roles)))
        else:
            user, role, first, last = fields
            if role not in self.roles:
                return "unknown role " + role
            first, last = int(first), int(last)
            if not 1 <= first <= last <= 365:
                return f"bad range {first} {last}"
            for name, cardinality, roles in self.ssd:
                for day in range(first, last + 1):
                    intersection = roles & self.closure(self.assigned(user, day) | {role})
                    if len(intersection) >= cardinality:
                        return f"ssd {name} day {day} roles " + ",".join(sorted(intersection))
            self.assignments.append((user, role, first, last))
        return None
