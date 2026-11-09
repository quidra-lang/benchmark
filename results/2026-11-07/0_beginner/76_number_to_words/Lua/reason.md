71000 becomes "seventy-one thousand", 300019 becomes "three hundred thousand nineteen", and whole input 0 becomes "zero". Zero hundreds/remainders contribute no component; only the whole-input special case emits zero. Nonempty components join with single spaces and the tens/units combination inserts its own hyphen.

small_words skips zero subparts, while number_words immediately returns "zero" for whole zero. Positive thousands/remainder guards and table.concat enforce spacing without extra zero components.

Whole-zero handling, hundreds/thousands/remainders and nonempty joins establish all three requested outputs. Numeric parsing and unrelated number cases add no evidence.
