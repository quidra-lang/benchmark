Month 1 begins at 1000000, increments month to 1, computes interest 10000, payment 50000, principal 40000 and next balance 960000. Its record is "month 1: interest=10000 principal=40000 balance=960000". The minimum cap makes a final partial payment equal balance+interest, leaving zero principal balance.

~/100 computes interest, math.min caps payment and the subsequent statements tie this month number, new balance and totals to the same record. No final aggregate output is needed to explain a monthly operation.

Initial balance/rate/payment, month increment, interest/principal/balance updates and output establish the first record and final-payment cap. Later month traces need not be enumerated.
