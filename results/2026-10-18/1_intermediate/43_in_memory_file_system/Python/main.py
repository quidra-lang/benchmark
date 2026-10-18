from itertools import groupby
import sys


DIRECTORY = "d"
FILE = "-"
LINK = "l"
NO_ENTRY = "No such file or directory"
NOT_DIRECTORY = "Not a directory"
TOO_MANY_LINKS = "Too many levels of symbolic links"
MAX_EXPANSIONS = 8
FIND_TYPES = {"f": FILE, "d": DIRECTORY, "l": LINK}
COUNT_FIELDS = "lwc"
REDIRECT_OPERATORS = (" >> ", " > ")


def parse_options(arguments):
    options = set()
    index = 0
    while index < len(arguments) and arguments[index].startswith("-"):
        options.update(arguments[index][1:])
        index += 1
    return options, arguments[index:]


def count_argument(arguments):
    if arguments and arguments[0] == "-n":
        return arguments[1], arguments[2:]
    return "10", arguments


def split_redirect(line):
    for operator in REDIRECT_OPERATORS:
        if operator in line:
            pipeline, path = line.split(operator)
            return pipeline, operator.strip(), path
    return line, None, None


def last_component(path):
    return path[path.rfind("/") + 1:]


def join_path(directory, name):
    if directory == "/":
        return "/" + name
    return directory + "/" + name


def byte_count(lines):
    return sum(len(line) + 1 for line in lines)


def word_count(lines):
    return sum(len(line.split()) for line in lines)


def count_line(counts, fields, name):
    parts = [str(counts[field]) for field in fields]
    if name is not None:
        parts.append(name)
    return " ".join(parts)


def numeric_value(line):
    sign = 1
    start = 0
    if line.startswith("-"):
        sign = -1
        start = 1
    end = start
    while end < len(line) and line[end].isdigit():
        end += 1
    if end == start:
        return 0
    return sign * int(line[start:end])


def glob_match(glob, name):
    glob_index = 0
    name_index = 0
    star_index = -1
    resume_index = 0
    while name_index < len(name):
        if glob_index < len(glob) and glob[glob_index] == "*":
            star_index = glob_index
            resume_index = name_index
            glob_index += 1
        elif glob_index < len(glob) and glob[glob_index] in ("?", name[name_index]):
            glob_index += 1
            name_index += 1
        elif star_index >= 0:
            glob_index = star_index + 1
            resume_index += 1
            name_index = resume_index
        else:
            return False
    while glob_index < len(glob) and glob[glob_index] == "*":
        glob_index += 1
    return glob_index == len(glob)


def is_descendant(node, ancestor):
    while node is not ancestor:
        if node.parent is node:
            return False
        node = node.parent
    return True


def collect_tree(node, display, name, depth, max_depth, visited):
    visited.append((display, name, node))
    if node.kind == DIRECTORY and (max_depth is None or depth < max_depth):
        for child_name, child in node.sorted_entries():
            child_display = join_path(display, child_name)
            collect_tree(child, child_display, child_name, depth + 1, max_depth, visited)


def directory_listing(directory, options):
    listing = []
    if "a" in options:
        listing.append((".", directory))
        listing.append(("..", directory.parent))
    for name, node in directory.sorted_entries():
        if "a" in options or not name.startswith("."):
            listing.append((name, node))
    if "t" in options:
        listing.sort(key=lambda entry: -entry[1].mtime)
    if "r" in options:
        listing.reverse()
    return listing


class Node:
    def __init__(self, kind, inode, mtime):
        self.kind = kind
        self.inode = inode
        self.mtime = mtime
        self.parent = self
        self.name = ""
        self.entries = {}
        self.lines = []
        self.target = ""

    def sorted_entries(self):
        return [(name, self.entries[name]) for name in sorted(self.entries)]

    def size(self):
        if self.kind == FILE:
            return byte_count(self.lines)
        if self.kind == LINK:
            return len(self.target)
        return len(self.entries)

    def link_count(self):
        if self.kind != DIRECTORY:
            return 1
        return 2 + sum(child.kind == DIRECTORY for child in self.entries.values())

    def usage(self):
        if self.kind != DIRECTORY:
            return self.size()
        total = 0
        for child in self.entries.values():
            total += child.usage()
        return total

    def type_name(self):
        if self.kind == DIRECTORY:
            return "directory"
        if self.kind == LINK:
            return "symbolic link"
        return "regular file" if self.lines else "regular empty file"


class Resolution:
    def __init__(self, node=None, reason=None, parent=None, name=None):
        self.node = node
        self.reason = reason
        self.parent = parent
        self.name = name

    def absent(self):
        return self.parent is not None


class Shell:
    def __init__(self):
        self.root = Node(DIRECTORY, 1, 0)
        self.cwd = self.root
        self.previous = None
        self.clock = 0
        self.next_inode = 2
        self.expansions = 0
        self.output = []
        self.stdout = []
        self.direct = False
        self.commands = {
            "pwd": self.pwd,
            "cd": self.cd,
            "mkdir": self.mkdir,
            "touch": self.touch,
            "echo": self.echo,
            "cat": self.cat,
            "ls": self.ls,
            "stat": self.stat,
            "rm": self.rm,
            "rmdir": self.rmdir,
            "mv": self.mv,
            "cp": self.cp,
            "ln": self.ln,
            "readlink": self.readlink,
            "realpath": self.realpath,
            "find": self.find,
            "du": self.du,
            "tree": self.tree,
            "wc": self.wc,
            "head": self.head,
            "tail": self.tail,
            "grep": self.grep,
            "sort": self.sort,
            "uniq": self.uniq,
        }

    def write(self, line):
        if self.direct:
            self.output.append(line)
        else:
            self.stdout.append(line)

    def error(self, message):
        self.output.append(message)

    def create(self, kind):
        node = Node(kind, self.next_inode, self.clock)
        self.next_inode += 1
        return node

    def attach(self, directory, name, node):
        directory.entries[name] = node
        directory.mtime = self.clock
        node.parent = directory
        node.name = name

    def detach(self, node):
        del node.parent.entries[node.name]
        node.parent.mtime = self.clock

    def replace_lines(self, node, lines):
        node.lines = list(lines)
        node.mtime = self.clock

    def append_lines(self, node, lines):
        node.lines.extend(lines)
        node.mtime = self.clock

    def absolute_path(self, node):
        names = []
        while node is not self.root:
            names.append(node.name)
            node = node.parent
        return "/" + "/".join(reversed(names))

    def contains_cwd(self, node):
        return is_descendant(self.cwd, node)

    def resolve(self, path, follow=True, make_parents=False):
        self.expansions = 0
        return self.walk(path, self.cwd, follow, make_parents, True)

    def walk(self, path, base, follow, make_parents, outermost):
        node = self.root if path.startswith("/") else base
        components = [part for part in path.split("/") if part]
        for index, component in enumerate(components):
            is_last = index == len(components) - 1
            if node.kind != DIRECTORY:
                return Resolution(reason=NOT_DIRECTORY)
            if component == ".":
                continue
            if component == "..":
                node = node.parent
                continue
            child = node.entries.get(component)
            if child is None:
                if outermost and is_last:
                    return Resolution(reason=NO_ENTRY, parent=node, name=component)
                if not (outermost and make_parents):
                    return Resolution(reason=NO_ENTRY)
                child = self.create(DIRECTORY)
                self.attach(node, component, child)
            if child.kind == LINK and (follow or not is_last):
                self.expansions += 1
                if self.expansions > MAX_EXPANSIONS:
                    return Resolution(reason=TOO_MANY_LINKS)
                expanded = self.walk(child.target, node, True, False, False)
                if expanded.node is None:
                    return expanded
                child = expanded.node
            node = child
        return Resolution(node=node)

    def is_directory_path(self, path):
        result = self.resolve(path)
        return result.node is not None and result.node.kind == DIRECTORY

    def read_inputs(self, command, paths, stdin):
        if not paths:
            yield None, stdin
        for path in paths:
            result = self.resolve(path)
            if result.node is None:
                self.error(f"{command}: {path}: {result.reason}")
            elif result.node.kind == DIRECTORY:
                self.error(f"{command}: {path}: Is a directory")
            else:
                yield path, result.node.lines

    def recursive_inputs(self, paths):
        for path in paths:
            result = self.resolve(path)
            if result.node is None:
                self.error(f"grep: {path}: {result.reason}")
                continue
            visited = []
            collect_tree(result.node, path, last_component(path), 0, None, visited)
            for display, _, node in visited:
                if node.kind == FILE:
                    yield display, node.lines

    def pwd(self, arguments, stdin):
        self.write(self.absolute_path(self.cwd))

    def cd(self, arguments, stdin):
        path = arguments[0] if arguments else "/"
        announce = path == "-"
        if announce:
            if self.previous is None:
                self.error("cd: OLDPWD not set")
                return
            path = self.previous
        result = self.resolve(path)
        if result.node is None:
            self.error(f"cd: {path}: {result.reason}")
        elif result.node.kind != DIRECTORY:
            self.error(f"cd: {path}: Not a directory")
        else:
            self.previous = self.absolute_path(self.cwd)
            self.cwd = result.node
            if announce:
                self.write(self.absolute_path(self.cwd))

    def mkdir(self, arguments, stdin):
        options, paths = parse_options(arguments)
        for path in paths:
            reason = self.make_directory(path, "p" in options)
            if reason is not None:
                self.error(f"mkdir: cannot create directory '{path}': {reason}")

    def make_directory(self, path, parents):
        result = self.resolve(path, False, parents)
        if result.absent():
            self.attach(result.parent, result.name, self.create(DIRECTORY))
            return None
        if result.node is None:
            return result.reason
        if parents and self.is_directory_path(path):
            return None
        return "File exists"

    def touch(self, arguments, stdin):
        for path in arguments:
            result = self.resolve(path)
            if result.absent():
                self.attach(result.parent, result.name, self.create(FILE))
            elif result.node is not None:
                result.node.mtime = self.clock
            else:
                self.error(f"touch: cannot touch '{path}': {result.reason}")

    def echo(self, arguments, stdin):
        self.write(arguments[0])

    def cat(self, arguments, stdin):
        for _, lines in self.read_inputs("cat", arguments, stdin):
            for line in lines:
                self.write(line)

    def ls(self, arguments, stdin):
        options, paths = parse_options(arguments)
        long_format = "l" in options
        if not paths:
            paths = ["."]
        for path in paths:
            result = self.resolve(path, not long_format)
            if result.node is None:
                self.error(f"ls: cannot access '{path}': {result.reason}")
            elif result.node.kind != DIRECTORY:
                self.display([(path, result.node)], long_format)
            else:
                if len(paths) > 1:
                    self.write(path + ":")
                self.display(directory_listing(result.node, options), long_format)

    def display(self, listing, long_format):
        if not long_format:
            for name, _ in listing:
                self.write(name)
            return
        rows = [
            (str(node.link_count()), str(node.size()), str(node.mtime))
            for _, node in listing
        ]
        widths = [max((len(row[column]) for row in rows), default=0) for column in range(3)]
        for (name, node), row in zip(listing, rows):
            values = [value.rjust(width) for value, width in zip(row, widths)]
            line = " ".join([node.kind] + values + [name])
            if node.kind == LINK:
                line += " -> " + node.target
            self.write(line)

    def stat(self, arguments, stdin):
        for path in arguments:
            result = self.resolve(path, False)
            if result.node is None:
                self.error(f"stat: cannot stat '{path}': {result.reason}")
                continue
            node = result.node
            self.write(
                f"{path}: {node.type_name()}, size {node.size()}, inode {node.inode}, "
                f"links {node.link_count()}, modified {node.mtime}"
            )

    def rm(self, arguments, stdin):
        options, paths = parse_options(arguments)
        for path in paths:
            if last_component(path) in (".", ".."):
                self.error(f"rm: refusing to remove '.' or '..' directory: skipping '{path}'")
                continue
            result = self.resolve(path, False)
            if result.node is None:
                if "f" not in options or result.reason != NO_ENTRY:
                    self.error(f"rm: cannot remove '{path}': {result.reason}")
            elif result.node.kind == DIRECTORY and "r" not in options:
                self.error(f"rm: cannot remove '{path}': Is a directory")
            elif self.contains_cwd(result.node):
                self.error(f"rm: cannot remove '{path}': Device or resource busy")
            else:
                self.detach(result.node)

    def rmdir(self, arguments, stdin):
        for path in arguments:
            reason = self.remove_directory(path)
            if reason is not None:
                self.error(f"rmdir: failed to remove '{path}': {reason}")

    def remove_directory(self, path):
        if last_component(path) in (".", ".."):
            return "Invalid argument"
        result = self.resolve(path, False)
        if result.node is None:
            return result.reason
        node = result.node
        if node.kind != DIRECTORY:
            return NOT_DIRECTORY
        if self.contains_cwd(node):
            return "Device or resource busy"
        if node.entries:
            return "Directory not empty"
        self.detach(node)
        return None

    def mv(self, arguments, stdin):
        sources, dest = arguments[:-1], arguments[-1]
        if len(sources) > 1 and not self.is_directory_path(dest):
            self.error(f"mv: target '{dest}' is not a directory")
            return
        for source in sources:
            self.move(source, dest)

    def move(self, source, dest):
        name = last_component(source)
        if name in (".", "..", ""):
            self.error(f"mv: cannot move '{source}' to '{dest}': Invalid argument")
            return
        found = self.resolve(source, False)
        if found.node is None:
            self.error(f"mv: cannot stat '{source}': {found.reason}")
            return
        moving = found.node
        target = self.resolve(dest)
        if target.node is not None and target.node.kind == DIRECTORY:
            directory = target.node
            shown = join_path(dest, name)
        else:
            place = self.resolve(dest, False)
            if place.absent():
                directory, name = place.parent, place.name
            elif place.node is not None:
                directory, name = place.node.parent, place.node.name
            else:
                self.error(f"mv: cannot move '{source}' to '{dest}': {place.reason}")
                return
            shown = dest
        existing = directory.entries.get(name)
        if moving.kind == DIRECTORY and is_descendant(directory, moving):
            self.error(f"mv: cannot move '{source}' to a subdirectory of itself, '{shown}'")
        elif existing is moving:
            self.error(f"mv: '{source}' and '{shown}' are the same file")
        elif existing is None:
            self.relocate(moving, directory, name)
        elif moving.kind == DIRECTORY and existing.kind != DIRECTORY:
            self.error(f"mv: cannot overwrite non-directory '{shown}' with directory '{source}'")
        elif moving.kind != DIRECTORY and existing.kind == DIRECTORY:
            self.error(f"mv: cannot overwrite directory '{shown}' with non-directory '{source}'")
        elif existing.kind == DIRECTORY and existing.entries:
            self.error(f"mv: cannot move '{source}' to '{shown}': Directory not empty")
        elif existing is self.cwd:
            self.error(f"mv: cannot move '{source}' to '{shown}': Device or resource busy")
        else:
            self.detach(existing)
            self.relocate(moving, directory, name)

    def relocate(self, node, directory, name):
        self.detach(node)
        self.attach(directory, name, node)

    def cp(self, arguments, stdin):
        options, operands = parse_options(arguments)
        sources, dest = operands[:-1], operands[-1]
        if len(sources) > 1 and not self.is_directory_path(dest):
            self.error(f"cp: target '{dest}' is not a directory")
            return
        for source in sources:
            self.copy(source, dest, "r" in options)

    def copy(self, source, dest, recursive):
        name = last_component(source)
        if name in (".", "..", ""):
            self.error(f"cp: cannot copy '{source}' to '{dest}': Invalid argument")
            return
        found = self.resolve(source)
        if found.node is None:
            self.error(f"cp: cannot stat '{source}': {found.reason}")
            return
        original = found.node
        if original.kind == DIRECTORY and not recursive:
            self.error(f"cp: -r not specified; omitting directory '{source}'")
            return
        target = self.resolve(dest)
        if target.node is not None and target.node.kind == DIRECTORY:
            shown = join_path(dest, name)
        elif target.node is not None or target.absent():
            shown = dest
        else:
            self.error(f"cp: cannot copy '{source}' to '{dest}': {target.reason}")
            return
        if original.kind == DIRECTORY:
            self.copy_directory(source, original, shown)
        else:
            self.copy_file(source, original, shown)

    def copy_directory(self, source, original, shown):
        place = self.resolve(shown, False)
        if place.node is not None:
            self.error(f"cp: cannot copy '{source}' to '{shown}': File exists")
        elif is_descendant(place.parent, original):
            self.error(f"cp: cannot copy a directory, '{source}', into itself, '{shown}'")
        else:
            self.clone(original, place.parent, place.name)

    def copy_file(self, source, original, shown):
        place = self.resolve(shown)
        if place.absent():
            self.clone(original, place.parent, place.name)
        elif place.node is None:
            self.error(f"cp: cannot copy '{source}' to '{shown}': {place.reason}")
        elif place.node is original:
            self.error(f"cp: '{source}' and '{shown}' are the same file")
        elif place.node.kind == DIRECTORY:
            self.error(f"cp: cannot overwrite directory '{shown}' with non-directory '{source}'")
        else:
            self.replace_lines(place.node, original.lines)

    def clone(self, original, directory, name):
        node = self.create(original.kind)
        node.lines = list(original.lines)
        node.target = original.target
        self.attach(directory, name, node)
        for child_name, child in original.sorted_entries():
            self.clone(child, node, child_name)

    def ln(self, arguments, stdin):
        target, path = arguments[1], arguments[2]
        result = self.resolve(path, False)
        if result.absent():
            link = self.create(LINK)
            link.target = target
            self.attach(result.parent, result.name, link)
        elif result.node is not None:
            self.error(f"ln: failed to create symbolic link '{path}': File exists")
        else:
            self.error(f"ln: failed to create symbolic link '{path}': {result.reason}")

    def readlink(self, arguments, stdin):
        path = arguments[0]
        result = self.resolve(path, False)
        if result.node is None:
            self.error(f"readlink: {path}: {result.reason}")
        elif result.node.kind != LINK:
            self.error(f"readlink: {path}: Invalid argument")
        else:
            self.write(result.node.target)

    def realpath(self, arguments, stdin):
        path = arguments[0]
        result = self.resolve(path)
        if result.node is None:
            self.error(f"realpath: {path}: {result.reason}")
        else:
            self.write(self.absolute_path(result.node))

    def find(self, arguments, stdin):
        path = "."
        if arguments and not arguments[0].startswith("-"):
            path, arguments = arguments[0], arguments[1:]
        tests = dict(zip(arguments[::2], arguments[1::2]))
        max_depth = int(tests["-maxdepth"]) if "-maxdepth" in tests else None
        result = self.resolve(path)
        if result.node is None:
            self.error(f"find: '{path}': {result.reason}")
            return
        start_name = "/" if path == "/" else last_component(path)
        visited = []
        collect_tree(result.node, path, start_name, 0, max_depth, visited)
        for display, name, node in visited:
            if "-name" in tests and not glob_match(tests["-name"], name):
                continue
            if "-type" in tests and node.kind != FIND_TYPES[tests["-type"]]:
                continue
            self.write(display)

    def du(self, arguments, stdin):
        options, paths = parse_options(arguments)
        for path in paths or ["."]:
            result = self.resolve(path)
            if result.node is None:
                self.error(f"du: cannot access '{path}': {result.reason}")
            else:
                self.report(result.node, path, options)

    def report(self, node, display, options):
        if "s" not in options:
            for name, child in node.sorted_entries():
                if child.kind == DIRECTORY or "a" in options:
                    self.report(child, join_path(display, name), options)
        self.write(f"{node.usage()} {display}")

    def tree(self, arguments, stdin):
        options, paths = parse_options(arguments)
        path = paths[0] if paths else "."
        result = self.resolve(path)
        if result.node is None:
            self.error(f"tree: {path}: {result.reason}")
            return
        if result.node.kind != DIRECTORY:
            self.error(f"tree: {path}: Not a directory")
            return
        self.write(path)
        directories, files = self.draw(result.node, "", "a" in options)
        directory_word = "directory" if directories == 1 else "directories"
        file_word = "file" if files == 1 else "files"
        self.write(f"{directories} {directory_word}, {files} {file_word}")

    def draw(self, directory, prefix, show_hidden):
        entries = [
            (name, node) for name, node in directory.sorted_entries()
            if show_hidden or not name.startswith(".")
        ]
        directories = 0
        files = 0
        for index, (name, node) in enumerate(entries):
            is_last = index == len(entries) - 1
            line = prefix + ("`-- " if is_last else "|-- ") + name
            if node.kind == LINK:
                line += " -> " + node.target
            self.write(line)
            if node.kind != DIRECTORY:
                files += 1
                continue
            directories += 1
            inner_prefix = prefix + ("    " if is_last else "|   ")
            inner_directories, inner_files = self.draw(node, inner_prefix, show_hidden)
            directories += inner_directories
            files += inner_files
        return directories, files

    def wc(self, arguments, stdin):
        options, paths = parse_options(arguments)
        fields = [field for field in COUNT_FIELDS if field in options] or list(COUNT_FIELDS)
        totals = dict.fromkeys(COUNT_FIELDS, 0)
        for name, lines in self.read_inputs("wc", paths, stdin):
            counts = {"l": len(lines), "w": word_count(lines), "c": byte_count(lines)}
            for field in COUNT_FIELDS:
                totals[field] += counts[field]
            self.write(count_line(counts, fields, name))
        if len(paths) > 1:
            self.write(count_line(totals, fields, "total"))

    def head(self, arguments, stdin):
        count, paths = count_argument(arguments)
        for _, lines in self.read_inputs("head", paths, stdin):
            if count.startswith("-"):
                selected = lines[:max(len(lines) - int(count[1:]), 0)]
            else:
                selected = lines[:int(count)]
            for line in selected:
                self.write(line)

    def tail(self, arguments, stdin):
        count, paths = count_argument(arguments)
        for _, lines in self.read_inputs("tail", paths, stdin):
            if count.startswith("+"):
                selected = lines[max(int(count[1:]), 1) - 1:]
            else:
                selected = lines[max(len(lines) - int(count), 0):]
            for line in selected:
                self.write(line)

    def grep(self, arguments, stdin):
        options, operands = parse_options(arguments)
        pattern, paths = operands[0], operands[1:]
        if "r" in options:
            sources = self.recursive_inputs(paths or ["."])
        else:
            sources = self.read_inputs("grep", paths, stdin)
        labeled = "r" in options or len(paths) > 1
        ignore_case = "i" in options
        if ignore_case:
            pattern = pattern.lower()
        for name, lines in sources:
            prefix = name + ":" if labeled else ""
            selected = []
            for number, line in enumerate(lines, 1):
                text = line.lower() if ignore_case else line
                if (pattern in text) != ("v" in options):
                    selected.append((number, line))
            if "c" in options:
                self.write(prefix + str(len(selected)))
                continue
            for number, line in selected:
                if "n" in options:
                    self.write(f"{prefix}{number}:{line}")
                else:
                    self.write(prefix + line)

    def sort(self, arguments, stdin):
        options, paths = parse_options(arguments)
        lines = []
        for _, content in self.read_inputs("sort", paths, stdin):
            lines.extend(content)
        if "n" in options:
            lines.sort(key=lambda line: (numeric_value(line), line))
        else:
            lines.sort()
        if "r" in options:
            lines.reverse()
        for line in lines:
            self.write(line)

    def uniq(self, arguments, stdin):
        options, paths = parse_options(arguments)
        for _, lines in self.read_inputs("uniq", paths, stdin):
            for line, group in groupby(lines):
                count = sum(1 for _ in group)
                self.write(f"{count} {line}" if "c" in options else line)

    def open_redirect(self, path, operator):
        result = self.resolve(path)
        if result.absent():
            node = self.create(FILE)
            self.attach(result.parent, result.name, node)
            return node
        if result.node is None:
            self.error(f"sh: {path}: {result.reason}")
            return None
        if result.node.kind == DIRECTORY:
            self.error(f"sh: {path}: Is a directory")
            return None
        if operator == ">":
            self.replace_lines(result.node, [])
        return result.node

    def run(self, command, stdin):
        words = command.split(" ")
        name = words[0]
        arguments = [command[len("echo "):]] if name == "echo" else words[1:]
        handler = self.commands.get(name)
        if handler is None:
            self.error(f"{name}: command not found")
        else:
            handler(arguments, stdin)

    def execute(self, line):
        self.clock += 1
        self.output.append(f"{self.absolute_path(self.cwd)}$ {line}")
        pipeline, operator, path = split_redirect(line)
        redirect = None
        if path is not None:
            redirect = self.open_redirect(path, operator)
            if redirect is None:
                return
        commands = pipeline.split(" | ")
        stdin = []
        for index, command in enumerate(commands):
            self.direct = redirect is None and index == len(commands) - 1
            self.stdout = []
            self.run(command, stdin)
            stdin = self.stdout
        if redirect is not None and stdin:
            self.append_lines(redirect, stdin)


def main():
    sys.setrecursionlimit(10000)
    shell = Shell()
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line == "exit":
            break
        shell.execute(line)
    if shell.output:
        sys.stdout.write("\n".join(shell.output) + "\n")


if __name__ == "__main__":
    main()
