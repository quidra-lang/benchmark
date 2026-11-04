# Task B selection — 30_set_operations / JavaScript

## Common answer requirements

Locate the third, labeled set-difference result and change only its membership direction to B minus A.

## Source evidence

The operand declarations establish that both inputs are sets, so the documented set-difference operation retains elements in its receiver that are absent from its argument. Exchange receiver and argument at the selected difference site. The stored result stays in its current position.

## Minimization

Selected complete lines of `main.js`: L1, L2, L5. The two declarations identify the actual collection type and support the documented operation in both operand directions. Other results and the existing sort and print steps are independent of this edit.

The selected excerpt measures **118 tokens** with `metric/tokenizer.py`.
