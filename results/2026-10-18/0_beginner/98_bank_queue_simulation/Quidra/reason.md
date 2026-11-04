# Task B selection: 98_bank_queue_simulation / Quidra

The question requires the first three interleaved generator draws, arrivals, teller-free times before assignment, separation of teller choice from start time, the first-teller equality rule, and the single indexed update. The seed, initial arrival/free array, customer loop, two generator updates and corresponding modular projections supply the exact inputs. The <= conditional chooses teller index 0 on equal free times, before math.max computes start from arrival and that chosen teller's free time. end = start + service and free[teller] = end update only the chosen entry; number = teller + 1 maps indices to displayed teller numbers.

The first six states are 2027382,1226992407,551494037,961371815,1404753842,2076553157. Arrivals are 3,6,9 and services 6,7,2. Customer 1 sees (0,0), chooses teller 1, starts 3, ends 9, leaving (9,0). Customer 2 sees (9,0), chooses teller 2, starts 6, ends 13, leaving (9,13). Customer 3 sees (9,13), chooses teller 1, starts 9, ends 11, leaving (11,13).

The Math import and documented integer math.max contract identify the same larger-of-two value as the original conditional, with no floating conversion. The other two max replacements affect overall reporting only and are not required for these three assignments. The selected integer-literal initializers and operations infer int and preserve the generator's exact integer arithmetic. Keeping overall wait aggregates, output formatting, or the full program is a larger sufficient alternative; omitting a random update or chosen-entry write would lose a requested fact.

Selected complete main.qui lines: 1, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 17, 20. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py on the current source: Task A 383; Task B 205. These are source-code token counts.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 383; Task B 205.

Measurement: Task A 383; Task B 205. Tokenizer: metric/tokenizer.py, unchanged.

The teller conditional has only integer-literal branches, so it infers int and preserves the exact generator arithmetic and array index.
