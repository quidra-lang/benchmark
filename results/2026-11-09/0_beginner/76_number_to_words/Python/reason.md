# Task B selection: 76_number_to_words / Python

## Answer requirements

Connect the below-one-thousand conversion with thousand-part composition for 71000 and 300019, comparing them with the special whole-input case 0. Explain which zero subparts produce no words, where zero instead produces the word zero, and how only nonempty components are joined. Derive the three word expressions and identify how spaces and any hyphen are supplied without an unwanted zero component.

## Answer and source evidence

71000 uses under_thousand(71)=seventy-one and an empty lower remainder, yielding `seventy-one thousand`. 300019 uses three hundred for the thousand part and nineteen below it, yielding `three hundred thousand nineteen`. Zero subparts add nothing; whole-input0 takes the special `zero` expression. Joining only present components introduces one space between words, and the tens/ones branch introduces the hyphen inside seventy-one. No zero word leaks into a positive composed number. The final named words value retains the completed expression.



Selected `main.py` lines: 2, 3, 5, 21, 31, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 53, 54, 55, 56, 57, 58. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
