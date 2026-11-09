from heap import CollectionRecord, by_address, first_fit, free_blocks, largest_free
from mark_sweep import mark


COLLECTION_STEPS = (("major", "minor"), ("full", "tenure"))
MARKING_KINDS = ("major", "full")
TENURING_KINDS = ("tenure", "full")


class Generational:
    def __init__(self, size, young, age):
        self.size = size
        self.young = young
        self.half = young // 2
        self.promotion_age = age
        self.base = 0
        self.top = 0
        self.target = 0
        self.objects = []
        self.records = []
        self.remembered = set()
        self.barriers = 0
        self.remembers = 0

    def is_young(self, obj):
        return obj.address < self.young

    def old_blocks(self):
        return free_blocks(self.objects, self.young, self.size)

    def free_list(self):
        blocks = []
        end = self.base + self.half
        if self.top < end:
            blocks.append((self.top, end - self.top))
        return blocks + self.old_blocks()

    def inactive_range(self):
        start = self.half - self.base
        return start, start + self.half

    def fits(self, obj):
        return self.top + obj.size <= self.base + self.half

    def place(self, obj):
        obj.address = self.top
        self.top += obj.size
        self.objects.append(obj)

    def allocate(self, obj, roots, line):
        if self.fits(obj):
            self.place(obj)
            return True
        for marking_kind, copying_kind in COLLECTION_STEPS:
            if largest_free(self.old_blocks()) < self.top - self.base:
                kind = marking_kind
            else:
                kind = copying_kind
            if not self.collect(kind, roots, line, obj.size):
                return False
            if self.fits(obj):
                self.place(obj)
                return True
        return False

    def write_barrier(self, target, value):
        if self.is_young(target):
            return
        self.barriers += 1
        if value is not None and self.is_young(value) and target not in self.remembered:
            self.remembered.add(target)
            self.remembers += 1

    def sweep_old(self, record):
        survivors = []
        for obj in self.objects:
            if self.is_young(obj):
                survivors.append(obj)
                continue
            record.work += 1
            if obj.marked:
                survivors.append(obj)
            else:
                record.freed.add(obj)
                self.remembered.discard(obj)
        self.objects = survivors

    def evacuate(self, obj, record, pending, queue):
        if obj is None or obj not in pending:
            return True
        pending.remove(obj)
        obj.age += 1
        obj.moves += 1
        if record.kind in TENURING_KINDS or obj.age >= self.promotion_age:
            address = first_fit(self.old_blocks(), obj.size)
            if address is None:
                return False
            obj.address = address
            record.promoted.add(obj)
        else:
            obj.address = self.target
            self.target += obj.size
        record.moved.add(obj)
        if record.kind not in MARKING_KINDS:
            record.live.add(obj)
        queue.append(obj)
        return True

    def evacuate_fields(self, obj, record, pending, queue):
        for child in obj.fields:
            if not self.evacuate(child, record, pending, queue):
                return False
        return True

    def collect(self, kind, roots, line, request):
        number = len(self.records) + 1
        record = CollectionRecord(number, line, request, kind, self.free_list())
        if kind in MARKING_KINDS:
            mark(record, roots, self.objects)
            self.sweep_old(record)
        pending = {obj for obj in self.objects if self.is_young(obj)}
        destination = self.half - self.base
        self.target = destination
        queue = []
        record.work += len(roots)
        for root in roots:
            if not self.evacuate(root, record, pending, queue):
                return False
        for obj in by_address(self.remembered):
            record.work += 1 + len(obj.fields)
            if not self.evacuate_fields(obj, record, pending, queue):
                return False
        index = 0
        while index < len(queue):
            obj = queue[index]
            index += 1
            record.work += obj.size + len(obj.fields)
            if not self.evacuate_fields(obj, record, pending, queue):
                return False
        survivors = []
        for obj in self.objects:
            if obj in pending:
                record.freed.add(obj)
            else:
                survivors.append(obj)
        self.objects = survivors
        self.base = destination
        self.top = self.target
        self.remembered = {obj for obj in self.objects if self.points_young(obj)}
        record.finish(self.free_list())
        self.records.append(record)
        return True

    def points_young(self, obj):
        if self.is_young(obj):
            return False
        return any(child is not None and self.is_young(child) for child in obj.fields)
