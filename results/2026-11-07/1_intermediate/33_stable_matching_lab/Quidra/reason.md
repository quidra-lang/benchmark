# Task B selection — Quidra

## Answer requirements shared across languages

1. Explain Boston acceptance across rounds, including persistent remaining capacity and why earlier acceptances cannot be displaced by later preferred applicants.
2. Explain how receiver preference determines current-round acceptance and how unacceptable applicants are rejected.
3. Identify exactly which attempts increment the reported applications count, including rejected or full-capacity attempts and excluding already matched/exhausted proposers.

## Selected source locations

- `main.qui`: 18, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 641, 642

## Evidence and language semantics

matching and remaining are outside the round loop, and applied is initialized inside it. Only unmatched proposers with a choice increment applications. Receiver preference iteration admits listed proposers only while remaining is positive. Acceptance writes a proposer's partner and consumes one remaining slot. Already accepted proposers never enter a subsequent round's applicant set, and the receiver considers only that fresh set, so earlier acceptances are never compared against later arrivals or evicted. A later preferred applicant is accepted only into an unused slot. Attempts to an unacceptable receiver or a full receiver still count because the increment precedes receiver screening; matched proposers and proposers without that round's choice do not attempt.

## Minimization and alternatives

The Boston operation is the smallest connected scope that establishes all three facts: initialization outside the loop, current-round reset and eligibility, and receiver admission/decrement. Deferred acceptance, manipulation searches and general market parsing are excluded. Short initializer/ranking/sequence helper implementations are included only where custom calls do not themselves establish sentinel, order or membership semantics; standard array/list/library operations need no implementation. Return/output lines connect the counter to the reported applications label.

The excerpt contains 430 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
