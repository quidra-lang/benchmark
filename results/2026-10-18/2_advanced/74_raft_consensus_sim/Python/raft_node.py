"""Persistent logs, volatile Raft state, node counters, and commands."""

from collections import namedtuple


Entry = namedtuple("Entry", "term command request")
STATISTICS = ("elections", "leader_terms", "votes_granted", "leader_ticks", "ae_ok",
              "ae_fail", "appended", "truncated", "applies")


class Node:
    def __init__(self, number):
        self.number = number
        self.term = 0
        self.voted_for = None
        self.log = []
        self.up = True
        self.stats = dict.fromkeys(STATISTICS, 0)
        self.reset_volatile()

    def reset_volatile(self):
        self.role = "FOLLOWER"
        self.commit = 0
        self.applied = 0
        self.store = {}
        self.known_leader = None
        self.votes = set()
        self.election_deadline = None
        self.election_record = None
        self.next = {}
        self.match = {}
        self.heartbeat_deadline = None
        self.quorum_deadline = None
        self.heard = set()
        self.cancel_transfer()

    def cancel_transfer(self):
        self.transfer_target = None
        self.transfer_sent = False
        self.transfer_deadline = None

    def crash(self):
        self.up = False
        self.reset_volatile()

    @property
    def last_index(self):
        return len(self.log)

    @property
    def last_term(self):
        return self.log[-1].term if self.log else 0

    def term_at(self, index):
        return self.log[index - 1].term if index else 0

    def accepts_log(self, last_index, last_term):
        return (last_term, last_index) >= (self.last_term, self.last_index)


def apply_command(store, command):
    operation = command[0]
    if operation == "NOOP":
        return None
    key = command[1]
    if operation == "SET":
        store[key] = command[2]
        return "ok"
    if operation == "ADD":
        store[key] = store.get(key, 0) + command[2]
        return store[key]
    if operation == "DEL":
        if key in store:
            del store[key]
            return "deleted"
        return "missing"
    return store.get(key, "missing")
