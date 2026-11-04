# Task B selection: 19_bmi_calculator / J

Mika’s height and weight are 165 and 70, giving integer products 700000 and 27225 and a real BMI of about 25.7117. It is at least 18.5 and 25 and below 30, so it is overweight. The numeric display is 25.7 with one decimal digit. This input is not a halfway case, so its result does not establish how the formatter breaks exact decimal ties.

The aligned vectors provide Mika’s height and weight. Dyadic % divides the two integer products; the first two conditions fail and the third assigns overweight. The J 8!:2 precision format is applied at output.

Complete main.ijs lines: 2, 3, 4, 5, 6, 7, 9, 10, 11, 13. The unused classification result arms and punctuation do not affect the named trace; retain the ordered conditions, the matching label and the separate output operation. Other records are unnecessary except where they share a source line with Mika. The benchmark tokenizer counts 212 tokens in this excerpt.
