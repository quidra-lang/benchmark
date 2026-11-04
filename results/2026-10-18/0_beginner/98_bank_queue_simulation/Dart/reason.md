# Task B selection — 98_bank_queue_simulation / Dart

## Common answer requirements

Trace the first three arrivals and teller free times, identify the tie rule and distinguish teller selection, service start and the one-slot update.

## Source evidence

From the initial state and the two random draws per customer, the first three arrivals are 3, 6, and 9. The free times before their assignments are (0, 0), (9, 0), and (9, 13). The first minimum wins on a tie, so the tellers are 1, 2, and 1. A separate maximum gives the service start, and assigning the end time to the chosen index leaves the other slot unchanged.

## Minimization

Selected complete lines of `main.dart`: L1, L4, L5, L6, L7, L8, L9, L10, L11, L12, L13, L15, L19. The selected RNG recurrence, initialization, selection and indexed write suffice for all three assignments. Retain the source expression that maps the zero-based selected index to the one-based teller number. Wait statistics and other output formatting contribute no answer fact. The import identifies the math alias used for the independent service-start maximum.

The selected excerpt measures **301 tokens** with `metric/tokenizer.py`.
