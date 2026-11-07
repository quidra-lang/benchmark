71000 becomes "seventy-one thousand", 300019 becomes "three hundred thousand nineteen", and whole input 0 becomes "zero". Zero hundreds/remainders contribute no component; only the whole-input special case emits zero. Nonempty components join with single spaces and the tens/units combination inserts its own hyphen.

under skips zero hundreds and y=0; the top-level n==0 branch adds the sole zero word while other parts require positive values. The named final words joins parts after composition.

Whole-zero handling, hundreds/thousands/remainders and nonempty joins establish all three requested outputs. Numeric parsing and unrelated number cases add no evidence.
