from heap import CollectionRecord, by_address, first_fit, free_blocks


def push_mark(record, stack, obj):
    obj.marked = True
    stack.append(obj)
    record.stack = max(record.stack, len(stack))


def mark(record, roots, objects):
    for obj in objects:
        obj.marked = False
    record.work += len(roots)
    stack = []
    for root in roots:
        if root is None or root.marked:
            continue
        push_mark(record, stack, root)
        while stack:
            obj = stack.pop()
            record.live.add(obj)
            record.work += 1 + len(obj.fields)
            for child in obj.fields:
                if child is not None and not child.marked:
                    push_mark(record, stack, child)


def sweep(record, objects):
    record.work += len(objects)
    survivors = []
    for obj in objects:
        if obj.marked:
            survivors.append(obj)
        else:
            record.freed.add(obj)
    return survivors


class MarkSweep:
    def __init__(self, size):
        self.size = size
        self.objects = []
        self.records = []

    def free_list(self):
        return free_blocks(self.objects, 0, self.size)

    def inactive_range(self):
        return 0, 0

    def allocate(self, obj, roots, line):
        address = first_fit(self.free_list(), obj.size)
        if address is None:
            self.collect(roots, line, obj.size)
            address = first_fit(self.free_list(), obj.size)
            if address is None:
                return False
        obj.address = address
        self.objects.append(obj)
        return True

    def collect(self, roots, line, request):
        number = len(self.records) + 1
        record = CollectionRecord(number, line, request, "sweep", self.free_list())
        mark(record, roots, self.objects)
        self.objects = sweep(record, self.objects)
        record.finish(self.free_list())
        self.records.append(record)


class MarkCompact:
    def __init__(self, size):
        self.size = size
        self.top = 0
        self.objects = []
        self.records = []

    def free_list(self):
        if self.top < self.size:
            return [(self.top, self.size - self.top)]
        return []

    def inactive_range(self):
        return 0, 0

    def allocate(self, obj, roots, line):
        if self.top + obj.size > self.size:
            self.collect(roots, line, obj.size)
            if self.top + obj.size > self.size:
                return False
        obj.address = self.top
        self.top += obj.size
        self.objects.append(obj)
        return True

    def collect(self, roots, line, request):
        number = len(self.records) + 1
        record = CollectionRecord(number, line, request, "compact", self.free_list())
        mark(record, roots, self.objects)
        record.work += len(self.objects) + len(roots)
        destination = 0
        survivors = []
        for obj in by_address(self.objects):
            if not obj.marked:
                record.freed.add(obj)
                continue
            record.work += len(obj.fields)
            if obj.address != destination:
                record.moved.add(obj)
                record.work += obj.size
                obj.address = destination
                obj.moves += 1
            destination += obj.size
            survivors.append(obj)
        self.objects = survivors
        self.top = destination
        record.finish(self.free_list())
        self.records.append(record)
