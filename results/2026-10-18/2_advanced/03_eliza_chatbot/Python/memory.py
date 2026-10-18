class MemoryQueue:
    def __init__(self, capacity):
        self.capacity = capacity
        self.texts = []
        self.log = []

    def copy(self):
        other = MemoryQueue(self.capacity)
        other.texts = list(self.texts)
        other.log = list(self.log)
        return other

    def store(self, prefix, keyword, text):
        if text in self.texts:
            self.log.append(f"{prefix} SKIP {keyword} {text}")
            return False
        if len(self.texts) == self.capacity:
            self.log.append(f"{prefix} DROP {self.texts.pop(0)}")
        self.texts.append(text)
        self.log.append(f"{prefix} STORE {keyword} {text}")
        return True

    def recall(self, prefix):
        text = self.texts.pop(0)
        self.log.append(f"{prefix} RECALL {text}")
        return text

    def clear(self, prefix):
        if self.texts:
            self.log.append(f"{prefix} CLEAR {len(self.texts)}")
            self.texts = []
