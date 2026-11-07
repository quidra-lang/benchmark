from fnmatch import fnmatchcase
import sys


ROOT_MESSAGE = "init"
HASH_BASE = 131
HASH_MODULUS = 2147483647
ARGUMENT_LIMITS = {"WRITE": 2, "COMMIT": 1, "AMEND": 1}
OPERATION_TITLES = {
    "merge": "Merging",
    "revert": "Reverting",
    "cherry-pick": "Cherry-picking",
}
DELETED_MARK = "(deleted)"


class CommandError(Exception):
    pass


def hash_commit(sequence, parents, tree, message):
    lines = [f"commit {sequence}"]
    lines.extend(f"parent {parent.id}" for parent in parents)
    lines.extend(f"file {path} {tree[path]}" for path in sorted(tree))
    lines.append(f"message {message}")
    value = 0
    for character in "".join(line + "\n" for line in lines):
        value = (value * HASH_BASE + ord(character)) % HASH_MODULUS
    return f"{value:08x}"


class Commit:
    def __init__(self, sequence, parents, tree, message):
        self.sequence = sequence
        self.parents = list(parents)
        self.tree = dict(tree)
        self.message = message
        self.id = hash_commit(sequence, self.parents, self.tree, message)

    def first_parent_tree(self):
        return self.parents[0].tree if self.parents else {}


class StashEntry:
    def __init__(self, label, base, tree):
        self.label = label
        self.base = base
        self.tree = tree


class Operation:
    def __init__(self, kind, commit):
        self.kind = kind
        self.commit = commit


def agree(first, second, path):
    return first.get(path) == second.get(path)


def differing_paths(first, second):
    paths = first.keys() | second.keys()
    return sorted(path for path in paths if not agree(first, second, path))


def match_path(target, source, path):
    if path in source:
        target[path] = source[path]
    else:
        target.pop(path, None)


def change_list(old, new):
    lines = []
    for path in differing_paths(old, new):
        if path not in old:
            lines.append(f"A {path}: {new[path]}")
        elif path not in new:
            lines.append(f"D {path}: {old[path]}")
        else:
            lines.append(f"M {path}: {old[path]} -> {new[path]}")
    return lines if lines else ["(no changes)"]


def conflict_content(ours, theirs, path):
    ours_text = ours.get(path, DELETED_MARK)
    theirs_text = theirs.get(path, DELETED_MARK)
    return f"<<<<<<< {ours_text} ======= {theirs_text} >>>>>>>"


def three_way_merge(base, ours, theirs):
    merged = {}
    conflicts = []
    for path in sorted(base.keys() | ours.keys() | theirs.keys()):
        if agree(theirs, base, path) or agree(ours, theirs, path):
            match_path(merged, ours, path)
        elif agree(ours, base, path):
            match_path(merged, theirs, path)
        else:
            conflicts.append(path)
            match_path(merged, ours, path)
    return merged, conflicts


def distances(start):
    result = {start: 0}
    queue = [start]
    position = 0
    while position < len(queue):
        commit = queue[position]
        position += 1
        for parent in commit.parents:
            if parent not in result:
                result[parent] = result[commit] + 1
                queue.append(parent)
    return result


def is_ancestor(candidate, commit):
    return candidate in distances(commit)


def reachable_from(roots):
    reachable = set()
    for root in roots:
        reachable.update(distances(root))
    return reachable


def merge_base(first, second):
    first_distances = distances(first)
    second_distances = distances(second)
    common = [commit for commit in first_distances if commit in second_distances]
    parents_of_common = {parent for commit in common for parent in commit.parents}
    candidates = [commit for commit in common if commit not in parents_of_common]
    return min(
        candidates,
        key=lambda commit: (
            max(first_distances[commit], second_distances[commit]),
            -commit.sequence,
        ),
    )


def state_letter(tree, path, content, missing):
    if path not in tree:
        return missing
    return "M" if tree[path] != content else "."


class Repository:
    def __init__(self):
        root = Commit(0, [], {}, ROOT_MESSAGE)
        self.created = 1
        self.commits = {root.id: root}
        self.branches = {"main": root}
        self.tags = {}
        self.head_branch = "main"
        self.detached = None
        self.work = {}
        self.index = {}
        self.conflicts = set()
        self.operation = None
        self.stash = []
        self.ignores = []
        self.output = []

    def emit(self, line):
        self.output.append(line)

    def emit_lines(self, lines):
        self.output.extend(lines)

    def head_commit(self):
        if self.head_branch is not None:
            return self.branches[self.head_branch]
        return self.detached

    def head_tree(self):
        return self.head_commit().tree

    def move_head(self, commit):
        if self.head_branch is not None:
            self.branches[self.head_branch] = commit
        else:
            self.detached = commit

    def location(self):
        return self.head_branch if self.head_branch is not None else "detached HEAD"

    def resolve(self, rev):
        anchor, _, steps = rev.partition("~")
        if anchor == "HEAD":
            commit = self.head_commit()
        elif anchor in self.branches:
            commit = self.branches[anchor]
        elif anchor in self.tags:
            commit = self.tags[anchor]
        elif anchor in self.commits:
            commit = self.commits[anchor]
        else:
            raise CommandError(f"unknown revision '{rev}'")
        for _ in range(int(steps) if steps else 0):
            if not commit.parents:
                raise CommandError(f"unknown revision '{rev}'")
            commit = commit.parents[0]
        return commit

    def summary(self, commit):
        references = []
        if self.head_branch is None and self.detached is commit:
            references.append("HEAD")
        elif self.head_branch is not None and self.branches[self.head_branch] is commit:
            references.append(f"HEAD -> {self.head_branch}")
        for name in sorted(self.branches):
            if self.branches[name] is commit and name != self.head_branch:
                references.append(name)
        for name in sorted(self.tags):
            if self.tags[name] is commit:
                references.append(f"tag: {name}")
        if references:
            return f"{commit.id} ({', '.join(references)}) {commit.message}"
        return f"{commit.id} {commit.message}"

    def is_ignored(self, path):
        if path in self.index or path in self.conflicts:
            return False
        return any(fnmatchcase(path, pattern) for pattern in self.ignores)

    def check_in_progress(self):
        if self.operation is not None:
            raise CommandError(f"{self.operation.kind} in progress")

    def has_uncommitted_changes(self):
        if self.index != self.head_tree():
            return True
        return any(not agree(self.work, self.index, path) for path in self.index)

    def check_uncommitted(self):
        if self.has_uncommitted_changes():
            raise CommandError("uncommitted changes")

    def check_overwrite(self, paths):
        head = self.head_tree()
        for path in sorted(paths):
            if not agree(self.index, head, path) or not agree(self.work, head, path):
                raise CommandError(f"local changes to '{path}' would be overwritten")

    def switch_tree(self, tree):
        changed = differing_paths(self.head_tree(), tree)
        self.check_overwrite(changed)
        for path in changed:
            match_path(self.index, tree, path)
            match_path(self.work, tree, path)

    def create_commit(self, parents, tree, message):
        commit = Commit(self.created, parents, tree, message)
        self.created += 1
        self.commits[commit.id] = commit
        return commit

    def record_commit(self, parents, tree, message):
        commit = self.create_commit(parents, tree, message)
        self.move_head(commit)
        old = commit.parents[0].tree
        new = commit.tree
        added = sum(path not in old for path in new)
        modified = sum(path in old and old[path] != new[path] for path in new)
        deleted = sum(path not in new for path in old)
        self.emit(
            f"[{self.location()} {commit.id}] {message} "
            f"({added} added, {modified} modified, {deleted} deleted)"
        )

    def apply(self, base, theirs, kind, target, message, parents, common=None):
        head = self.head_tree()
        merged, conflicts = three_way_merge(base, head, theirs)
        changed = differing_paths(head, merged)
        self.check_overwrite(set(changed) | set(conflicts))
        if kind == "merge":
            self.emit(f"Merge base {common.id}")
        elif not conflicts and merged == head:
            self.emit("nothing to commit")
            return
        for path in changed:
            match_path(self.index, merged, path)
            match_path(self.work, merged, path)
        if not conflicts:
            self.record_commit(parents, merged, message)
            return
        for path in conflicts:
            self.work[path] = conflict_content(head, theirs, path)
            self.emit(f"CONFLICT {path}")
        self.conflicts = set(conflicts)
        self.operation = Operation(kind, target)
        if kind == "merge":
            self.emit("Automatic merge failed; fix conflicts and then commit the result.")
        elif kind == "revert":
            self.emit(f"error: could not revert {target.id}")
        else:
            self.emit(f"error: could not apply {target.id}")

    def write(self, arguments):
        path, text = arguments
        self.work[path] = text

    def remove(self, arguments):
        path = arguments[0]
        if path not in self.work:
            raise CommandError(f"no such file '{path}'")
        del self.work[path]

    def add(self, arguments):
        path = arguments[0]
        if path == "ALL":
            self.add_all()
            return
        if path in self.work and self.is_ignored(path):
            raise CommandError(f"path '{path}' is ignored")
        if path not in self.work and path not in self.index and path not in self.conflicts:
            raise CommandError(f"pathspec '{path}' did not match any files")
        match_path(self.index, self.work, path)
        self.conflicts.discard(path)

    def add_all(self):
        candidates = self.work.keys() | self.index.keys()
        paths = [path for path in candidates if not self.is_ignored(path)]
        for path in paths:
            match_path(self.index, self.work, path)
        self.conflicts = set()

    def rm(self, arguments):
        path = arguments[0]
        if path not in self.index:
            raise CommandError(f"pathspec '{path}' did not match any files")
        del self.index[path]
        self.work.pop(path, None)
        self.conflicts.discard(path)

    def unstage(self, arguments):
        path = arguments[0]
        head = self.head_tree()
        if path not in self.index and path not in head:
            raise CommandError(f"pathspec '{path}' did not match any files")
        match_path(self.index, head, path)

    def restore(self, arguments):
        path = arguments[0]
        if len(arguments) == 1:
            if path not in self.index:
                raise CommandError(f"pathspec '{path}' did not match any files")
            self.work[path] = self.index[path]
            return
        rev = arguments[1]
        tree = self.resolve(rev).tree
        if path not in tree:
            raise CommandError(f"path '{path}' does not exist in '{rev}'")
        self.index[path] = tree[path]
        self.work[path] = tree[path]
        self.conflicts.discard(path)

    def ignore(self, arguments):
        self.ignores.append(arguments[0])

    def commit(self, arguments):
        message = arguments[0]
        if self.conflicts:
            raise CommandError("unresolved conflicts")
        head = self.head_commit()
        if self.operation is not None and self.operation.kind == "merge":
            self.record_commit([head, self.operation.commit], self.index, message)
            self.operation = None
        elif self.index == head.tree:
            self.emit("nothing to commit")
        else:
            self.record_commit([head], self.index, message)
            self.operation = None

    def amend(self, arguments):
        self.check_in_progress()
        head = self.head_commit()
        if not head.parents:
            raise CommandError("cannot amend the root commit")
        self.record_commit(head.parents, self.index, arguments[0])

    def status(self, arguments):
        head = self.head_commit()
        if self.head_branch is not None:
            self.emit(f"On branch {self.head_branch}")
        else:
            self.emit(f"HEAD detached at {head.id}")
        if self.operation is not None:
            title = OPERATION_TITLES[self.operation.kind]
            self.emit(f"{title} {self.operation.commit.id}")
        lines = []
        paths = head.tree.keys() | self.index.keys() | self.work.keys() | self.conflicts
        for path in sorted(paths):
            if path in self.conflicts:
                lines.append(f"UU {path}")
            elif path in self.index:
                content = self.index[path]
                staged = state_letter(head.tree, path, content, "A")
                unstaged = state_letter(self.work, path, content, "D")
                if staged != "." or unstaged != ".":
                    lines.append(f"{staged}{unstaged} {path}")
            else:
                if path in head.tree:
                    lines.append(f"D. {path}")
                if path in self.work and not self.is_ignored(path):
                    lines.append(f"?? {path}")
        if lines:
            self.emit_lines(lines)
        else:
            self.emit("nothing to commit, working tree clean")

    def ls(self, arguments):
        tree = self.resolve(arguments[0]).tree if arguments else self.work
        if not tree:
            self.emit("(empty)")
        for path in sorted(tree):
            self.emit(f"{path} {tree[path]}")

    def cat(self, arguments):
        path = arguments[0]
        if len(arguments) == 1:
            if path not in self.work:
                raise CommandError(f"no such file '{path}'")
            self.emit(self.work[path])
            return
        rev = arguments[1]
        tree = self.resolve(rev).tree
        if path not in tree:
            raise CommandError(f"path '{path}' does not exist in '{rev}'")
        self.emit(tree[path])

    def diff(self, arguments):
        if not arguments:
            tracked = {path: self.work[path] for path in self.index if path in self.work}
            self.emit_lines(change_list(self.index, tracked))
        elif arguments[0] == "STAGED":
            self.emit_lines(change_list(self.head_tree(), self.index))
        else:
            old = self.resolve(arguments[0])
            new = self.resolve(arguments[1])
            self.emit_lines(change_list(old.tree, new.tree))

    def log(self, arguments):
        limit = int(arguments[0]) if arguments else None
        commit = self.head_commit()
        printed = 0
        while True:
            self.emit(self.summary(commit))
            printed += 1
            if not commit.parents or printed == limit:
                break
            commit = commit.parents[0]

    def show(self, arguments):
        commit = self.resolve(arguments[0] if arguments else "HEAD")
        self.emit(f"commit {self.summary(commit)}")
        if commit.parents:
            parents = " ".join(parent.id for parent in commit.parents)
        else:
            parents = "none"
        self.emit(f"parents: {parents}")
        self.emit_lines(change_list(commit.first_parent_tree(), commit.tree))

    def blame(self, arguments):
        path = arguments[0]
        commit = self.head_commit()
        if path not in commit.tree:
            raise CommandError(f"path '{path}' does not exist in 'HEAD'")
        content = commit.tree[path]
        while commit.parents and commit.parents[0].tree.get(path) == content:
            commit = commit.parents[0]
        self.emit(f"{commit.id} ({commit.message}) {content}")

    def branch(self, arguments):
        if arguments[0] == "-d":
            self.delete_branch(arguments[1])
            return
        name = arguments[0]
        if name in self.branches:
            raise CommandError(f"branch '{name}' already exists")
        commit = self.resolve(arguments[1] if len(arguments) == 2 else "HEAD")
        self.branches[name] = commit
        self.emit(f"Created branch {name} at {commit.id}")

    def delete_branch(self, name):
        if name not in self.branches:
            raise CommandError(f"no such branch '{name}'")
        if name == self.head_branch:
            raise CommandError(f"cannot delete current branch '{name}'")
        commit = self.branches[name]
        if not is_ancestor(commit, self.head_commit()):
            raise CommandError(f"branch '{name}' is not fully merged")
        del self.branches[name]
        self.emit(f"Deleted branch {name} (was {commit.id})")

    def list_branches(self, arguments):
        if self.head_branch is None:
            self.emit(f"* (HEAD detached at {self.detached.id})")
        for name in sorted(self.branches):
            commit = self.branches[name]
            mark = "*" if name == self.head_branch else " "
            self.emit(f"{mark} {name} {commit.id} {commit.message}")

    def tag(self, arguments):
        if arguments[0] == "-d":
            self.delete_tag(arguments[1])
            return
        name = arguments[0]
        if name in self.tags:
            raise CommandError(f"tag '{name}' already exists")
        commit = self.resolve(arguments[1] if len(arguments) == 2 else "HEAD")
        self.tags[name] = commit
        self.emit(f"Created tag {name} at {commit.id}")

    def delete_tag(self, name):
        if name not in self.tags:
            raise CommandError(f"no such tag '{name}'")
        commit = self.tags.pop(name)
        self.emit(f"Deleted tag {name} (was {commit.id})")

    def list_tags(self, arguments):
        if not self.tags:
            self.emit("(no tags)")
        for name in sorted(self.tags):
            commit = self.tags[name]
            self.emit(f"{name} {commit.id} {commit.message}")

    def switch(self, arguments):
        name = arguments[0]
        if name not in self.branches:
            raise CommandError(f"no such branch '{name}'")
        if name == self.head_branch:
            self.emit(f"Already on '{name}'")
            return
        self.check_in_progress()
        self.switch_tree(self.branches[name].tree)
        self.head_branch = name
        self.detached = None
        self.emit(f"Switched to branch '{name}'")

    def detach(self, arguments):
        commit = self.resolve(arguments[0])
        self.check_in_progress()
        self.switch_tree(commit.tree)
        self.head_branch = None
        self.detached = commit
        self.emit(f"HEAD is now at {commit.id} {commit.message}")

    def merge(self, arguments):
        rev = arguments[0]
        theirs = self.resolve(rev)
        self.check_in_progress()
        ours = self.head_commit()
        if is_ancestor(theirs, ours):
            self.emit("Already up to date")
            return
        if is_ancestor(ours, theirs):
            self.switch_tree(theirs.tree)
            self.move_head(theirs)
            self.emit(f"Fast-forward {ours.id}..{theirs.id}")
            return
        self.check_uncommitted()
        common = merge_base(ours, theirs)
        self.apply(
            common.tree, theirs.tree, "merge", theirs,
            f"Merge {rev}", [ours, theirs], common,
        )

    def show_merge_base(self, arguments):
        first = self.resolve(arguments[0])
        second = self.resolve(arguments[1])
        self.emit(merge_base(first, second).id)

    def rebase(self, arguments):
        upstream = self.resolve(arguments[0])
        self.check_in_progress()
        head = self.head_commit()
        if is_ancestor(upstream, head):
            self.emit("Already up to date")
            return
        self.check_uncommitted()
        upstream_ancestors = distances(upstream)
        replayed = []
        commit = head
        while commit not in upstream_ancestors:
            replayed.append(commit)
            commit = commit.parents[0]
        replayed.reverse()
        tree = upstream.tree
        picked_trees = []
        for commit in replayed:
            merged, conflicts = three_way_merge(commit.parents[0].tree, tree, commit.tree)
            if conflicts:
                raise CommandError(
                    f"could not rebase {commit.id}: conflict in '{conflicts[0]}'"
                )
            if merged == tree:
                picked_trees.append(None)
            else:
                picked_trees.append(merged)
                tree = merged
        self.switch_tree(tree)
        tip = upstream
        for commit, picked in zip(replayed, picked_trees):
            if picked is None:
                self.emit(f"skip {commit.id} {commit.message}")
            else:
                created = self.create_commit([tip], picked, commit.message)
                self.emit(f"pick {commit.id} -> {created.id} {commit.message}")
                tip = created
        self.move_head(tip)
        self.emit(f"HEAD is now at {tip.id} {tip.message}")

    def reset(self, arguments):
        mode, rev = arguments
        commit = self.resolve(rev)
        tree = commit.tree
        if mode == "HARD":
            for path in self.index.keys() | tree.keys() | self.conflicts:
                match_path(self.work, tree, path)
        if mode != "SOFT":
            self.index = dict(tree)
        self.move_head(commit)
        self.conflicts = set()
        self.operation = None
        self.emit(f"HEAD is now at {commit.id} {commit.message}")

    def revert(self, arguments):
        commit = self.resolve(arguments[0])
        self.check_in_progress()
        self.check_uncommitted()
        self.apply(
            commit.tree, commit.first_parent_tree(), "revert", commit,
            f'Revert "{commit.message}"', [self.head_commit()],
        )

    def cherry_pick(self, arguments):
        commit = self.resolve(arguments[0])
        self.check_in_progress()
        self.check_uncommitted()
        self.apply(
            commit.first_parent_tree(), commit.tree, "cherry-pick", commit,
            commit.message, [self.head_commit()],
        )

    def stash_command(self, arguments):
        if not arguments:
            self.save_stash()
        elif arguments[0] == "POP":
            self.pop_stash()
        elif arguments[0] == "DROP":
            self.drop_stash()
        else:
            self.list_stash()

    def save_stash(self):
        self.check_in_progress()
        if not self.has_uncommitted_changes():
            self.emit("No local changes to save")
            return
        head = self.head_commit()
        tracked = sorted(self.index.keys() | head.tree.keys())
        saved = {path: self.work[path] for path in tracked if path in self.work}
        for path in tracked:
            match_path(self.work, head.tree, path)
        self.index = dict(head.tree)
        location = self.head_branch if self.head_branch is not None else "(no branch)"
        label = f"WIP on {location}: {head.id} {head.message}"
        self.stash.insert(0, StashEntry(label, head, saved))
        self.emit(f"Saved stash@{{0}}: {label}")

    def pop_stash(self):
        if not self.stash:
            raise CommandError("no stash entries")
        self.check_in_progress()
        self.check_uncommitted()
        entry = self.stash[0]
        head = self.head_tree()
        merged, conflicts = three_way_merge(entry.base.tree, head, entry.tree)
        if conflicts:
            raise CommandError(f"stash conflict in '{conflicts[0]}'")
        changed = differing_paths(head, merged)
        self.check_overwrite(changed)
        for path in changed:
            match_path(self.work, merged, path)
        del self.stash[0]
        self.emit(f"Restored stash@{{0}}: {entry.label}")
        self.emit_lines(change_list(head, merged))

    def drop_stash(self):
        if not self.stash:
            raise CommandError("no stash entries")
        entry = self.stash.pop(0)
        self.emit(f"Dropped stash@{{0}}: {entry.label}")

    def list_stash(self):
        if not self.stash:
            self.emit("(no stash entries)")
        for position, entry in enumerate(self.stash):
            self.emit(f"stash@{{{position}}}: {entry.label}")

    def graph(self, arguments):
        roots = [self.head_commit(), *self.branches.values(), *self.tags.values()]
        reachable = sorted(
            reachable_from(roots), key=lambda commit: commit.sequence, reverse=True
        )
        lanes = []
        for commit in reachable:
            if commit not in lanes:
                lanes.append(commit)
            position = lanes.index(commit)
            symbols = []
            for index, lane in enumerate(lanes):
                if index == position:
                    symbols.append("*")
                elif lane is commit:
                    symbols.append("/")
                else:
                    symbols.append("|")
            self.emit(f"{' '.join(symbols)} {self.summary(commit)}")
            lanes = [
                lane for index, lane in enumerate(lanes)
                if index == position or lane is not commit
            ]
            if not commit.parents:
                del lanes[position]
                continue
            lanes[position] = commit.parents[0]
            if len(commit.parents) == 2 and commit.parents[1] not in lanes:
                lanes.insert(position + 1, commit.parents[1])

    def describe(self, arguments):
        commit = self.resolve(arguments[0] if arguments else "HEAD")
        ancestors = distances(commit)
        best_name = None
        best_distance = 0
        for name in sorted(self.tags):
            target = self.tags[name]
            if target in ancestors and (best_name is None or ancestors[target] < best_distance):
                best_name = name
                best_distance = ancestors[target]
        if best_name is None:
            raise CommandError(f"no tag can describe '{commit.id}'")
        if best_distance == 0:
            self.emit(best_name)
        else:
            self.emit(f"{best_name}-{best_distance}-g{commit.id}")

    def gc(self, arguments):
        roots = [self.head_commit(), *self.branches.values(), *self.tags.values()]
        roots.extend(entry.base for entry in self.stash)
        if self.operation is not None:
            roots.append(self.operation.commit)
        kept = reachable_from(roots)
        removed = [key for key, commit in self.commits.items() if commit not in kept]
        for key in removed:
            del self.commits[key]
        self.emit(f"Removed unreachable commits: {len(removed)}")

    def execute(self, line):
        command = line.split(" ", 1)[0]
        arguments = line.split(" ", ARGUMENT_LIMITS.get(command, -1))[1:]
        handlers = {
            "WRITE": self.write,
            "REMOVE": self.remove,
            "ADD": self.add,
            "RM": self.rm,
            "UNSTAGE": self.unstage,
            "RESTORE": self.restore,
            "IGNORE": self.ignore,
            "COMMIT": self.commit,
            "AMEND": self.amend,
            "STATUS": self.status,
            "LS": self.ls,
            "CAT": self.cat,
            "DIFF": self.diff,
            "LOG": self.log,
            "SHOW": self.show,
            "BLAME": self.blame,
            "BRANCH": self.branch,
            "BRANCHES": self.list_branches,
            "TAG": self.tag,
            "TAGS": self.list_tags,
            "SWITCH": self.switch,
            "DETACH": self.detach,
            "MERGE": self.merge,
            "MERGEBASE": self.show_merge_base,
            "REBASE": self.rebase,
            "RESET": self.reset,
            "REVERT": self.revert,
            "CHERRYPICK": self.cherry_pick,
            "STASH": self.stash_command,
            "GRAPH": self.graph,
            "DESCRIBE": self.describe,
            "GC": self.gc,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    repository = Repository()
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line == "EXIT":
            break
        repository.execute(line)
    if repository.output:
        sys.stdout.write("\n".join(repository.output) + "\n")


if __name__ == "__main__":
    main()
