class Container:
    def __init__(self, message_id):
        self.id = message_id
        self.message = None
        self.parent = None
        self.children = []
        self.subject = None

    def is_ancestor_or_self(self, other):
        while other is not None:
            if other is self:
                return True
            other = other.parent
        return False


def adopt(parent, child):
    child.parent = parent
    parent.children.append(child)


class Threader:
    def __init__(self):
        self.table = {}
        self.containers = []

    def container_of(self, message_id):
        if message_id not in self.table:
            container = Container(message_id)
            self.table[message_id] = container
            self.containers.append(container)
        return self.table[message_id]

    def add(self, message):
        if message.id:
            container = self.container_of(message.id)
        else:
            container = Container("")
            self.containers.append(container)
        container.message = message
        references = [self.container_of(reference) for reference in message.references]
        for current, following in zip(references, references[1:]):
            if following.parent is None and not following.is_ancestor_or_self(current):
                adopt(current, following)
        if container.parent is not None:
            container.parent.children.remove(container)
            container.parent = None
        if references and not container.is_ancestor_or_self(references[-1]):
            adopt(references[-1], container)

    def roots(self):
        return [container for container in self.containers if container.parent is None]


def prune(containers, at_root):
    result = []
    for container in containers:
        container.children = prune(container.children, False)
        if container.message is not None or at_root and len(container.children) >= 2:
            result.append(container)
            continue
        for child in container.children:
            child.parent = None if at_root else container.parent
        result.extend(container.children)
    return result


def container_key(container):
    if container.message is not None:
        return container.message.sort_key
    return min(container_key(child) for child in container.children)


def sort_containers(containers):
    for container in containers:
        sort_containers(container.children)
    containers.sort(key=container_key)


def root_subject(root):
    if root.message is not None:
        return root.message.base_subject
    return root.children[0].message.base_subject


def merge_group(subject, group):
    missing = [root for root in group if root.message is None]
    originals = [root for root in group if root.message is not None and not root.message.reply]
    if missing:
        target = missing[0]
    elif len(originals) == 1:
        target = originals[0]
    else:
        target = Container("")
        target.subject = subject
    for root in group:
        if root is target:
            continue
        if root.message is not None:
            adopt(target, root)
        else:
            for child in root.children:
                adopt(target, child)
    return target


def merge_by_subject(roots):
    groups = {}
    for root in roots:
        subject = root_subject(root)
        if subject:
            groups.setdefault(subject, []).append(root)
    merged = []
    for root in roots:
        subject = root_subject(root)
        if not subject or len(groups[subject]) == 1:
            merged.append(root)
    for subject, group in groups.items():
        if len(group) >= 2:
            merged.append(merge_group(subject, group))
    return merged


def build_threads(messages):
    threader = Threader()
    for message in messages:
        threader.add(message)
    roots = prune(threader.roots(), True)
    sort_containers(roots)
    roots = merge_by_subject(roots)
    sort_containers(roots)
    return roots
