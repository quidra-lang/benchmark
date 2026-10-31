"""Iterative unification with an explicit reversible binding trail."""

from terms import Compound, Variable, dereference


class Trail:
    def __init__(self):
        self.bindings = []

    def mark(self):
        return len(self.bindings)

    def undo(self, mark):
        while len(self.bindings) > mark:
            self.bindings.pop().binding = None

    def unify(self, left, right):
        pending = [(left, right)]
        while pending:
            left, right = pending.pop()
            left, right = dereference(left), dereference(right)
            if left is right:
                continue
            if isinstance(left, Variable):
                left.binding = right
                self.bindings.append(left)
            elif isinstance(right, Variable):
                right.binding = left
                self.bindings.append(right)
            elif isinstance(left, Compound) and isinstance(right, Compound):
                if left.name != right.name or len(left.args) != len(right.args):
                    return False
                pending.extend(reversed(list(zip(left.args, right.args))))
            elif type(left) is not type(right) or left != right:
                return False
        return True


def identical(left, right):
    pending = [(left, right)]
    while pending:
        left, right = pending.pop()
        left, right = dereference(left), dereference(right)
        if left is right:
            continue
        if isinstance(left, Variable) or isinstance(right, Variable):
            return False
        if isinstance(left, Compound) and isinstance(right, Compound):
            if left.name != right.name or len(left.args) != len(right.args):
                return False
            pending.extend(reversed(list(zip(left.args, right.args))))
        elif type(left) is not type(right) or left != right:
            return False
    return True
