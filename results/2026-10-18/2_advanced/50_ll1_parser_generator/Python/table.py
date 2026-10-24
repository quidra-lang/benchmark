"""Production numbering, PREDICT sets, parse-table cells and conflict types."""

from first_follow import first_sequence, terminal_order
from grammar_parser import format_production


def number_productions(grammar):
    numbered = []
    for lhs in grammar["order"]:
        for rhs in grammar["rules"][lhs]:
            numbered.append({
                "number": len(numbered) + 1,
                "lhs": lhs, "rhs": rhs,
                "notation": format_production(lhs, rhs),
            })
    return numbered


def build_table(grammar, sets):
    """Record every competing prediction, with FIRST preferred over FOLLOW."""
    productions = number_productions(grammar)
    cells = {
        (lhs, token): []
        for lhs in grammar["order"]
        for token in sets["terminals"] + ["$"]
    }
    for item in productions:
        direct, empty = first_sequence(
            item["rhs"], sets["nullable"], sets["first"]
        )
        predicts = {}
        for token in direct:
            predicts[token] = "FIRST"
        if empty:
            for token in sets["follow"][item["lhs"]]:
                predicts.setdefault(token, "FOLLOW")
        item["predict"] = predicts
        for token in terminal_order(predicts):
            cells[(item["lhs"], token)].append({
                "number": item["number"],
                "reason": predicts[token],
            })
    choices = {}
    conflicts = []
    for lhs in grammar["order"]:
        for token in sets["terminals"] + ["$"]:
            entries = cells[(lhs, token)]
            if not entries:
                continue
            preferred = [
                item for item in entries if item["reason"] == "FIRST"
            ]
            choices[(lhs, token)] = (
                preferred[0] if preferred else entries[0]
            )["number"]
            if len(entries) >= 2:
                reasons = {item["reason"] for item in entries}
                kind = (
                    "FIRST/FIRST" if reasons == {"FIRST"}
                    else "FOLLOW/FOLLOW" if reasons == {"FOLLOW"}
                    else "FIRST/FOLLOW"
                )
                conflicts.append({
                    "lhs": lhs, "token": token,
                    "kind": kind, "entries": entries,
                    "chosen": choices[(lhs, token)],
                })
    return {
        "productions": productions,
        "cells": cells,
        "choices": choices,
        "conflicts": conflicts,
    }
