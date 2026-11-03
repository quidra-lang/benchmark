"""Five-stage timing and ordered attribution of all stall cycles."""

from hazards import id_resolved, ready_cycle


CAUSES = ("control", "structural", "load_use", "raw")
STAGES = ("IF", "ID", "EX", "MEM", "WB")


def simulate(instructions, sources, variant, mispredicted):
    timings = []
    records = []
    delays = []
    for index, instruction in enumerate(instructions):
        execute = variant["latency"] if instruction["class"] == "MUL" else 1
        if index == 0:
            fetch, decode, start = 1, 2, 3
        else:
            previous = timings[-1]
            if mispredicted[index - 1]:
                fetch = previous["X"] + int(not id_resolved(instructions[index - 1], variant))
            else:
                fetch = previous["D"]
            decode = max(fetch + 1, previous["X"])
            ideal = previous["X"] + 1
            load_ready = ideal
            raw_ready = ideal
            load_producer = None
            raw_producer = None
            for source in sources[index]:
                producer = source["producer"]
                if producer is None:
                    continue
                ready = ready_cycle(instruction, instructions[producer], timings[producer], variant)
                if instructions[producer]["class"] == "LOAD":
                    if ready > load_ready:
                        load_ready, load_producer = ready, producer
                elif ready > raw_ready:
                    raw_ready, raw_producer = ready, producer
            bounds = (decode + 1, previous["M"], load_ready, raw_ready)
            start = ideal
            for cause, bound, producer in zip(CAUSES, bounds, (None, None, load_producer, raw_producer)):
                if bound > start:
                    records.append({"cause": cause, "cycles": bound - start,
                                    "responsible": index - 1 if cause in ("control", "structural") else index,
                                    "waiting": index, "producer": producer})
                    start = bound
            delays.append(start - ideal)
        timings.append({"F": fetch, "D": decode, "X": start,
                        "M": start + execute, "W": start + execute + 1})
    if instructions[-1]["class"] == "MUL" and variant["latency"] >= 2:
        records.append({"cause": "structural", "cycles": variant["latency"] - 1,
                        "responsible": len(instructions) - 1, "waiting": None, "producer": None})
    return {"timings": timings, "records": records, "delays": delays, "cycles": timings[-1]["W"]}
