# Task B selection: 78_bank_account / Quidra

The question requires the balances before both Emma-to-Nina transfers, their equality boundary, the lack of balance changes on failure, and the immediately following Emma withdrawal. The selected fixtures give Emma's deposit, Nina's earlier transfer, the two Emma transfers and Emma's withdrawal; unrelated Leo-only withdrawals and later transactions cannot affect these balances. The names and balances associate all indices with holders. Splitting, integer parsing and index lookup connect these fixtures to the deposit, insufficient-funds, debit and transfer-credit branches.

Emma first has 800 + 1200 = 2000; Nina has 12000 - 5000 = 7000. The 2500 transfer fails because amount > balance, and its branch only marks failure. The 2000 transfer succeeds at equality, debiting Emma to 0 and crediting Nina to 9000. The following 300 withdrawal fails and leaves Emma at 0. Both debit and transfer credit occur only in the success else branch. Native array indexing and the documented first-match collections.index contract establish the account mapping.

The original packed fixture rows forced unrelated commands into the excerpt. A full-source or contiguous-span alternative adds more unrelated commands and display code. Keeping all fixture lines is unnecessary because each omitted transaction operates only on accounts outside the preceding dependencies or occurs later. The complete Task A sequence is unchanged; this selection is an evidence slice, not a replacement runnable fixture.

Selected complete main.qui lines: 1, 3, 4, 5, 6, 8, 10, 11, 12, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **513** tokens; Task B **327** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
