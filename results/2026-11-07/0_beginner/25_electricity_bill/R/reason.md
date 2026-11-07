# Task B: 25_electricity_bill / R

Suzuki uses 120 kWh: basic 900 plus 120×30 = 4500. Tanaka uses 300: basic 900 +120×30 +180×36 =10980. The middle tier receives only usage beyond 120, capped at the next boundary; higher-tier usage likewise receives only its excess. Each completed bill enters the total once, so its already included basic charge is not added again.

The vectorized bills expression uses pmin/pmax for disjoint excess ranges; sum(bills) accumulates complete bills once.

Evidence is from `main.R`, L1,L2,L3,L5.

- L1: `names <- c("Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe")`
- L2: `usages <- c(85, 120, 254, 300, 438, 176)`
- L3: `bills <- 900 + pmin(usages, 120) * 30 + pmin(pmax(usages - 120, 0), 180) * 36 + pmax(usages - 300, 0) * 40`
- L5: `cat(sprintf("total: %d yen\n", sum(bills)))`

Minimization: The named customer data, tier formula and total update are necessary; per-customer line formatting contributes nothing to the billing allocation question. The selected complete original lines, in source order, cost 170 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 212, and the complete source costs 212. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
