# Task B selection: 25_electricity_bill / Quidra

## Answer requirements

Trace the basic charge and marginal tiers for the supplied 120 and 300 kWh inputs.

## Source evidence and supported analysis

The basic charge starts at 900. Suzuki's 120 kWh takes the first branch, adding 120*30=3600 and giving 4500 yen. Tanaka's 300 kWh takes the second branch, adding 120*30 + (300-120)*36 = 10080 and giving 10980 yen. The inclusive threshold and subtraction of the first 120 kWh prevent full-usage higher-tier charging. Native array zip binds each name with its corresponding usage and checks equal lengths before any bill processing; it changes no tier arithmetic. Input data and output format are outside this excerpt because Task B itself supplies the two usages.

Selected complete `main.qui` lines: 5, 6, 7, 8, 9. All excerpt lines are verbatim and in source order. Ordinary language and documented package semantics apply. User-defined operations are supported by their selected statements when they are change dependencies; unaffected formatting helpers need no modification.

## Selection and measurement

The selected input/state bindings, bounds, decisions, arithmetic and output change sites support the requested answer. Unrelated unchanged source is omitted. The complete source and enclosing span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **266** tokens; Task B **78** tokens. These are lexical evidence measurements; execution verification is recorded separately.
