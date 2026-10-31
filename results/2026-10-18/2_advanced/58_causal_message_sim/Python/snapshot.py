"""Chandy-Lamport record storage, cuts, orphans, transit and money."""

from collections import Counter


def new_snapshot(name, start, sources):
    return {
        "name": name, "start": start, "complete": None,
        "records": {}, "channel_states": {
            (source, destination): [] for source in sources for destination
            in sources if source != destination
        },
        "markers": {}, "accepted": set(), "ignored": [],
    }


def record_state(snapshot, process, time, reason):
    name = process["name"]
    snapshot["records"][name] = {
        "time": time, "reason": reason, "balance": process["balance"],
        "lamport": process["lamport"],
        "vector": list(process["vector"]),
        "pending": list(process["holdback"]),
    }


def accepted_marker(snapshot, source, destination, time, processes):
    snapshot["accepted"].add((source, destination))
    snapshot["markers"][(source, destination)]["accepted"] = time
    if len(snapshot["accepted"]) == len(processes) * (len(processes) - 1):
        snapshot["complete"] = time


def snapshot_cut(snapshot, names, index):
    return [
        snapshot["records"][name]["vector"][index[name]]
        for name in names
    ]


def cut_details(cut, names, processes, copies):
    indices = {name: i for i, name in enumerate(names)}
    orphan = []
    transit = []
    for copy in copies:
        send = copy["send_event"]
        sent = send["local_number"] <= cut[indices[copy["source"]]]
        received = (
            copy.get("recv_event") is not None
            and copy["recv_event"]["local_number"]
            <= cut[indices[copy["destination"]]]
        )
        if received and not sent:
            orphan.append(copy)
        if sent and not received:
            transit.append(copy)
    balances = sum(
        processes[name]["initial"] if cut[i] == 0
        else processes[name]["events"][cut[i] - 1]["balance"]
        for i, name in enumerate(names)
    )
    money = balances + sum(copy["amount"] for copy in transit)
    return {
        "orphans": orphan, "transit": transit,
        "balances": balances, "money": money,
        "consistent": not orphan,
    }


def recorded_copies(snapshot, channel_order):
    channel_entries = [
        copy for pair in channel_order for copy in snapshot["channel_states"][pair]
    ]
    pending = [
        copy for item in snapshot["records"].values()
        for copy in item["pending"]
    ]
    return channel_entries, pending


def transit_match(channel_copies, pending_copies, transit):
    identifier = lambda copy: (copy["message"]["id"], copy["destination"])
    return (
        Counter(map(identifier, channel_copies + pending_copies))
        == Counter(map(identifier, transit))
    )


def vector_consistent(snapshot, names, index, cut):
    return all(
        value <= cut[i]
        for name in names
        for i, value in enumerate(snapshot["records"][name]["vector"])
    )


def copy_label(copy):
    return f"m{copy['message']['id']}->{copy['destination']}"
