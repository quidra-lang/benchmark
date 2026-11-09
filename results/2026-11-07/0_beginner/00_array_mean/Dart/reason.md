The named mean remains numeric before display; formatting fixes two fractional digits (including a trailing zero), and a single line-writing operation adds the newline without a field separator or trailing space.

/ produces a double; toStringAsFixed(2) supplies two digits and print adds one newline.

Both the numeric mean binding and its output conversion are needed to distinguish stored value from display text. The formatting/line-writing call establishes padding and newline behavior without its library implementation.
