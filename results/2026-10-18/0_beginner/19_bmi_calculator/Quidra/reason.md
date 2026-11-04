# Task B selection — 19_bmi_calculator / Quidra

Mika contributes height 165 and weight 70. The integer products are 700000 and 27225. Both are converted to real before division, giving an unrounded BMI of about 25.7117. The thresholds 18.5 and 25.0 do not match, and the threshold 30.0 does, so the category is overweight. Only the output interpolation applies half-up rounding to one fractional digit, displaying 25.7. The other fixture rows and the fallback category cannot affect Mika's result.

Selected complete source lines in order are 1, 4, 8, 9, 10, 11, 12, 13, 16.

Tokenizer: Task A 252 tokens; Task B 170 tokens.

Measurement: Task A 252; Task B 170. Tokenizer: metric/tokenizer.py, unchanged.
