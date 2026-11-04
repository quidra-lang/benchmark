# Task B selection: 85_text_justify / Quidra

The question asks where and how to reverse remainder-space distribution while keeping greedy packing, base spacing, final/single-word padding, width and framing. The Text import identifies the package contract, and the typed successful string[] binding identifies its justify(source, 30) call. The documented text.layout.justify signature offers extra_right = true, which assigns remainder spaces from the right only on nonfinal multiword lines; the default is false. Changing that named option at the call satisfies the requirement. The unchanged caller loop and vertical-bar print do not require modification.

The result binding is necessary for this pinned compiler: justify returns string[] | error, while foreach expects an array. A successful typed binding unwraps the error union with normal propagation. It preserves string element information and does not implement the proposed Task B change. The direct import-plus-call boundary is smaller than including the paragraph, iteration and formatting code, and all required layout behavior follows from the documented package contract.

Selected complete main.qui lines: 1, 4. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **177** tokens; Task B **21** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
