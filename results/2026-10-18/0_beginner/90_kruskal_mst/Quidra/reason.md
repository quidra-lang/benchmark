# Task B selection: 90_kruskal_mst / Quidra

The question requires the Union-Find decisions at weights 5 and 6, the final accepted edge, the seventh-acceptance break, and the meaning of skipped. The typed edge data for weights 2 through 10 and name mapping support the whole relevant decision prefix; weights 11, 12, 14 and 16 are not examined. The sort-key extraction and ascending sort establish that order. Each root walk follows the parent links; equal roots increment skipped and continue, while unequal roots merge through parent[second] = first.

Weight 5 joins E's existing A-C-E component to D, so D-E is accepted. Weight 6 C-D then has equal roots and is skipped. The accepted weights are 2, 3, 4, 5, 7, 8 and 10, with weight 9 also rejected; E-H at weight 10 is the seventh accepted edge. accepted == 7 breaks immediately, so skipped is 2 and excludes the four remaining edges. All edge tuples remain present in Task A, in their original order.

Native range, integer indexing and control flow, plus documented collections.push and stable sorting semantics, suffice without their implementations. One edge per physical line removes unrelated high-weight data from the dependency slice while retaining typed tuples. Keeping all thirteen tuples, or keeping the original packed lines, costs more without supporting another answer requirement. The root helper body is necessary because its name and int result do not by themselves establish the connectivity test.

Selected complete main.qui lines: 1, 4, 5, 6, 7, 9, 10, 11, 12, 13, 15, 16, 17, 20, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 42, 43, 44. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **499** tokens; Task B **359** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
