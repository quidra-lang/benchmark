teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]
matches = [
    "Lions 0-3 Bears",
    "Tigers 2-2 Wolves",
    "Eagles 4-0 Sharks",
    "Bears 0-1 Sharks",
    "Wolves 2-1 Eagles",
    "Lions 0-1 Tigers",
    "Tigers 3-3 Bears",
    "Eagles 2-2 Lions",
    "Sharks 2-2 Wolves",
    "Bears 3-1 Wolves",
    "Lions 2-0 Sharks",
    "Tigers 2-1 Eagles",
    "Eagles 1-0 Bears",
    "Sharks 2-0 Tigers",
    "Wolves 2-1 Lions",
]
fields = ["played", "wins", "draws", "losses", "gf", "ga", "points"]
stats = {name: dict.fromkeys(fields, 0) for name in teams}
for match in matches:
    home, score, away = match.split()
    h, a = map(int, score.split("-"))
    for name, goals, conceded in [(home, h, a), (away, a, h)]:
        record = stats[name]
        record["played"] += 1
        record["gf"] += goals
        record["ga"] += conceded
        if goals > conceded:
            record["wins"] += 1
            record["points"] += 3
        elif goals == conceded:
            record["draws"] += 1
            record["points"] += 1
        else:
            record["losses"] += 1


def ranking_key(name):
    s = stats[name]
    return (-s["points"], s["ga"] - s["gf"], -s["gf"], name)


ordered = sorted(teams, key=ranking_key)
for position, name in enumerate(ordered, 1):
    s = stats[name]
    difference = s["gf"] - s["ga"]
    gd = f"+{difference}" if difference > 0 else str(difference)
    print(
        f"{position}. {name} P={s['played']} W={s['wins']} D={s['draws']} L={s['losses']} "
        f"GF={s['gf']} GA={s['ga']} GD={gd} Pts={s['points']}"
    )
