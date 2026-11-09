71000 becomes "seventy-one thousand", 300019 becomes "three hundred thousand nineteen", and whole input 0 becomes "zero". Zero hundreds/remainders contribute no component; only the whole-input special case emits zero. Nonempty components join with single spaces and the tens/units combination inserts its own hyphen.

under_thousand adds hundreds and positive remainder only; the top-level parts excludes a zero lower thousand block and uses SMALL[0] only when no parts exist. The table and hyphen rule establish the exact words.

Whole-zero handling, hundreds/thousands/remainders and nonempty joins establish all three requested outputs. Numeric parsing and unrelated number cases add no evidence.
