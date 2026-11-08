# Task B selection — Java

## Answer requirements shared across languages

1. Explain Boston acceptance across rounds, including persistent remaining capacity and why earlier acceptances cannot be displaced by later preferred applicants.
2. Explain how receiver preference determines current-round acceptance and how unacceptable applicants are rejected.
3. Identify exactly which attempts increment the reported applications count, including rejected or full-capacity attempts and excluding already matched/exhausted proposers.

## Selected source locations

- `Main.java`: 41, 47, 48, 49, 50, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 624

## Evidence and language semantics

emptyMatching fills -1. partners/remaining persist across rounds; current applicants reset. Receiver preference iteration admits only listed proposers, and applications counts submissions before acceptance. Acceptance writes a proposer's partner and consumes one remaining slot. Already accepted proposers never enter a subsequent round's applicant set, and the receiver considers only that fresh set, so earlier acceptances are never compared against later arrivals or evicted. A later preferred applicant is accepted only into an unused slot. Attempts to an unacceptable receiver or a full receiver still count because the increment precedes receiver screening; matched proposers and proposers without that round's choice do not attempt.

## Minimization and alternatives

The Boston operation is the smallest connected scope that establishes all three facts: initialization outside the loop, current-round reset and eligibility, and receiver admission/decrement. Deferred acceptance, manipulation searches and general market parsing are excluded. Short initializer/ranking/sequence helper implementations are included only where custom calls do not themselves establish sentinel, order or membership semantics; standard array/list/library operations need no implementation. Return/output lines connect the counter to the reported applications label.

The excerpt contains 585 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
