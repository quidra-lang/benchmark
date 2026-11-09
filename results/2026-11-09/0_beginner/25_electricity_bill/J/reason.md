# Task B: 25_electricity_bill / J

Suzuki uses 120 kWh: basic 900 plus 120×30 = 4500. Tanaka uses 300: basic 900 +120×30 +180×36 =10980. The middle tier receives only usage beyond 120, capped at the next boundary; higher-tier usage likewise receives only its excess. Each completed bill enters the total once, so its already included basic charge is not added again.

The selected parallel names/usages identify both customers; the loop computes a whole bill then adds that bill once to total.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8.

- L2: `names =. ;:'Sato Suzuki Takahashi Tanaka Ito Watanabe'`
- L3: `usages =. 85 120 254 300 438 176`
- L4: `total =. 0`
- L5: `for_i. i.6 do.`
- L6: `usage =. i{usages`
- L7: `bill =. 900 + (30*usage<.120) + (36*180<.0>.usage-120) + 40*0>.usage-300`
- L8: `total =. total+bill`

Minimization: The named customer data, tier formula and total update are necessary; per-customer line formatting contributes nothing to the billing allocation question. The selected complete original lines, in source order, cost 138 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 138, and the complete source costs 225. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
