from heap import CollectionRecord


class Copying:
    def __init__(self, size):
        self.size = size
        self.half = size // 2
        self.base = 0
        self.top = 0
        self.objects = []
        self.records = []

    def free_list(self):
        end = self.base + self.half
        if self.top < end:
            return [(self.top, end - self.top)]
        return []

    def inactive_range(self):
        start = self.half - self.base
        return start, start + self.half

    def fits(self, obj):
        return self.top + obj.size <= self.base + self.half

    def allocate(self, obj, roots, line):
        if not self.fits(obj):
            self.collect(roots, line, obj.size)
            if not self.fits(obj):
                return False
        obj.address = self.top
        self.top += obj.size
        self.objects.append(obj)
        return True

    def copy(self, obj, record, copied, queue):
        if obj is None or obj in copied:
            return
        copied.add(obj)
        obj.address = self.top
        self.top += obj.size
        obj.moves += 1
        record.live.add(obj)
        record.moved.add(obj)
        queue.append(obj)

    def collect(self, roots, line, request):
        number = len(self.records) + 1
        record = CollectionRecord(number, line, request, "copy", self.free_list())
        self.base = self.half - self.base
        self.top = self.base
        copied = set()
        queue = []
        record.work += len(roots)
        for root in roots:
            self.copy(root, record, copied, queue)
        index = 0
        while index < len(queue):
            obj = queue[index]
            index += 1
            record.work += obj.size + len(obj.fields)
            for child in obj.fields:
                self.copy(child, record, copied, queue)
        for obj in self.objects:
            if obj not in copied:
                record.freed.add(obj)
        self.objects = queue
        record.finish(self.free_list())
        self.records.append(record)
