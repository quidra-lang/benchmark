# Task B selection: 19_bmi_calculator / Rust

Mika’s height and weight are 165 and 70, giving integer products 700000 and 27225 and a real BMI of about 25.7117. It is at least 18.5 and 25 and below 30, so it is overweight. The numeric display is 25.7 with one decimal digit. This input is not a halfway case, so its result does not establish how the formatter breaks exact decimal ties.

The record and integer calculations supply the products. The f64 conversion is before division. The first two tests fail, the third chooses overweight and the separate formatting precision is one fractional digit.

Complete main.rs lines: 2, 5, 9, 10, 11, 12, 14, 16, 17, 21. The unused classification result arms and punctuation do not affect the named trace; retain the ordered conditions, the matching label and the separate output operation. Other records are unnecessary except where they share a source line with Mika. The benchmark tokenizer counts 193 tokens in this excerpt.
