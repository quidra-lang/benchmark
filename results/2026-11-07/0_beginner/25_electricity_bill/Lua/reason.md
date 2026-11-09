Suzuki at 120 kWh pays 900+120*30=4500 yen. Tanaka at 300 pays 900+120*30+180*36=10980 yen. Only usage above each boundary reaches the next rate, and adding the completed bill once to total already includes exactly one basic charge.

The first min caps at 120, the second min/max clamps excess to 0..180 and the final max charges only usage above 300. The named bill feeds total exactly once.

The two boundary usages, basic charge, tier branches and total update establish exactly-once charging. Unrelated customer calculations and report fields are omitted.
