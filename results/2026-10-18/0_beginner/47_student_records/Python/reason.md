# Task B selection: 47_student_records / Python

## Common answer requirements

Replace competition ranking with consecutive ranks for distinct totals, preserving existing ordering and tie sharing.

## Source evidence

The loop enumerates sorted records from one. The current rank is assigned the enumeration index only when total differs from previous, skipping positions after ties. Keep the distinct-total check and increment the rank by one there, starting from zero. Continue saving the previous total each iteration.

## Minimization

The enumeration header explains what index means and why copying it skips a rank. The unchanged sort and print calls need no edit. Selected complete lines of `main.py`: 13, 14, 15, 16, 17, 20.
