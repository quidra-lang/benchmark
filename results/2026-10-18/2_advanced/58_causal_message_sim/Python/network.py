"""Ordered directed channels, deterministic MINSTD delay and packet statistics."""

from pathlib import Path


class MINSTD:
    def __init__(self, seed):
        self.state = seed
        self.draws = 0

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        self.draws += 1
        return self.state


def read_topology(path="input/topology.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    header = lines[0].split(" ")
    names = header[1:]
    indices = {name: index for index, name in enumerate(names)}
    channels = {}
    for line in lines[1:]:
        _, source, destination, kind, *numbers = line.split()
        minimum = int(numbers[0])
        maximum = int(numbers[1]) if len(numbers) == 2 else minimum
        channels[(source, destination)] = {
            "source": source, "destination": destination,
            "kind": kind, "minimum": minimum, "maximum": maximum,
            "sequence": 0, "last_arrival": 0, "messages": 0,
            "markers": 0, "buffered": 0, "max_delay": 0,
            "entries": 0, "previous_vector": [0] * len(names),
        }
    order = sorted(channels, key=lambda pair: (
        indices[pair[0]], indices[pair[1]]
    ))
    return names, channels, order


def dispatch(channels, source, destination, packet, time, generator, enqueue):
    """Assign sequence/delay, register channel statistics, schedule arrival."""
    channel = channels[(source, destination)]
    channel["sequence"] += 1
    packet["sequence"] = channel["sequence"]
    packet["source"] = source
    packet["destination"] = destination
    packet["dispatch_time"] = time
    minimum, maximum = channel["minimum"], channel["maximum"]
    if minimum == maximum:
        delay = minimum
    else:
        delay = minimum + generator.draw() % (maximum - minimum + 1)
    arrival = time + delay
    if channel["kind"] == "FIFO":
        arrival = max(arrival, channel["last_arrival"])
    channel["last_arrival"] = max(channel["last_arrival"], arrival)
    packet["arrival_time"] = arrival
    channel["max_delay"] = max(channel["max_delay"], arrival - time)
    if packet["packet_type"] == "marker":
        channel["markers"] += 1
    else:
        channel["messages"] += 1
        previous = channel["previous_vector"]
        vector = packet["send_event"]["vector"]
        channel["entries"] += sum(
            a != b for a, b in zip(previous, vector)
        )
        channel["previous_vector"] = list(vector)
    enqueue(arrival, destination, "arrival", packet)
    return packet


def delay_notation(channel):
    if channel["minimum"] == channel["maximum"]:
        return str(channel["minimum"])
    return f"{channel['minimum']}-{channel['maximum']}"
