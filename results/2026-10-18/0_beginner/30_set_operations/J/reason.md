# Task B selection: 30_set_operations / J

Reverse only the standalone A-minus-B result to B-minus-A. Keep the third result labeled difference and preserve uniqueness, increasing order, and the other three operations.

The b binding is deduplicated by Nub, which is needed because Less filters its left argument. Reverse only the operands in the labeled Less operation; its ascending sort and output remain fixed.

Complete main.ijs lines: 2, 5. The edit location alone is insufficient where deduplication, order or label association depends on a different operation or a specific collection type. The unchanged input literals are only retained when inseparable from that type or deduplication evidence. The benchmark tokenizer counts 45 tokens in this excerpt.
