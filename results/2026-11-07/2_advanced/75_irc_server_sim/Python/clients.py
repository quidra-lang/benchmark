from collections import deque


class Client:
    def __init__(self, identifier, hostname, time, capacity):
        self.identifier = identifier
        self.hostname = hostname
        self.connection_time = time
        self.nickname = None
        self.username = None
        self.realname = ""
        self.invisible = False
        self.registered = False
        self.registration_time = None
        self.last_received = time
        self.last_speaking = None
        self.ping_sent = None
        self.tokens = capacity
        self.refill_time = None
        self.queue = deque()
        self.channels = []
        self.invites = []
        self.away = ""
        self.received = 0
        self.sent = 0
        self.active = True

    @property
    def addressee(self):
        return self.nickname if self.nickname is not None else "*"

    @property
    def prefix(self):
        return f"{self.nickname}!{self.username}@{self.hostname}"

    @property
    def mode(self):
        return "+i" if self.invisible else "+"

    def use_token(self, time, capacity, interval):
        if self.tokens == capacity:
            self.refill_time = time + interval
        self.tokens -= 1

    def refill(self, time, capacity, interval):
        if self.refill_time == time:
            self.tokens += 1
            self.refill_time = time + interval if self.tokens < capacity else None
