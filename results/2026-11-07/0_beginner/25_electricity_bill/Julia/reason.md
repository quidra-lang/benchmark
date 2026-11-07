# Task B: 25_electricity_bill / Julia

Suzuki uses 120 kWh: basic 900 plus 120×30 = 4500. Tanaka uses 300: basic 900 +120×30 +180×36 =10980. The middle tier receives only usage beyond 120, capped at the next boundary; higher-tier usage likewise receives only its excess. Each completed bill enters the total once, so its already included basic charge is not added again.

The household tuples identify both cases. The tier expression bounds each usage contribution and total += bill accumulates the complete result.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L2: `total = 0`
- L3: `households = [`
- L4: `("Sato", 85),`
- L5: `("Suzuki", 120),`
- L6: `("Takahashi", 254),`
- L7: `("Tanaka", 300),`
- L8: `("Ito", 438),`
- L9: `("Watanabe", 176),`
- L10: `]`
- L11: `for (name, usage) in households`
- L12: `bill =`
- L13: `900 + min(usage, 120)*30 + min(max(usage-120, 0), 180)*36 + max(usage-300, 0)*40`
- L14: `total += bill`

Minimization: The named customer data, tier formula and total update are necessary; per-customer line formatting contributes nothing to the billing allocation question. The selected complete original lines, in source order, cost 192 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 192, and the complete source costs 259. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
