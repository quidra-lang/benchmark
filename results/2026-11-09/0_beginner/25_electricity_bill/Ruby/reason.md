Suzuki at 120 kWh pays 900+120*30=4500 yen. Tanaka at 300 pays 900+120*30+180*36=10980 yen. Only usage above each boundary reaches the next rate, and adding the completed bill once to total already includes exactly one basic charge.

The min/max clamps divide usage into 120, the next at most 180, and excess above 300. total starts at 0 and total += bill adds the whole named amount once.

The two boundary usages, basic charge, tier branches and total update establish exactly-once charging. Unrelated customer calculations and report fields are omitted.
