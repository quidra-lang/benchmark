# Task B selection: 38_insertion_sort_steps / C#

shifts starts at zero for the step and increments once inside the loop that copies one existing value one position right. The later write of the extracted value lies after that loop and performs no increment. At i=1 the moved 52 counts once, while placing 17 does not count as another right shift.

Keep initialization, the shift loop and final insertion/update boundary to establish the unit and absence of a second increment. Full input and presentation are unnecessary because the question supplies the step.

Selected complete source lines in `Program.cs`: 10, 11, 12, 13, 14, 15, 16, 17, 18. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
