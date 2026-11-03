"""Lamport and vector clocks, causal broadcast stamps and vector notation."""


def nonreceive_event(process, own_index):
    process["lamport"] += 1
    process["vector"][own_index] += 1


def receive_event(process, own_index, sender_event):
    process["lamport"] = max(
        process["lamport"], sender_event["lamport"]
    ) + 1
    process["vector"] = [
        max(a, b) for a, b in zip(process["vector"],
                                  sender_event["vector"])
    ]
    process["vector"][own_index] += 1


def less_equal(a, b):
    return all(x <= y for x, y in zip(a, b))


def happens_before(a, b):
    return a != b and less_equal(a, b)


def relation(a, b):
    if happens_before(a, b):
        return "->"
    if happens_before(b, a):
        return "<-"
    return "||"


def broadcast_deliverable(stamp, received, source_index):
    return all(
        stamp[k] == received[k] + 1 if k == source_index
        else stamp[k] <= received[k]
        for k in range(len(stamp))
    )


def missing_indices(stamp, received, source_index):
    return [
        k for k in range(len(stamp))
        if stamp[k] > received[k] + (1 if k == source_index else 0)
    ]


def vector_text(vector):
    return ",".join(map(str, vector))
