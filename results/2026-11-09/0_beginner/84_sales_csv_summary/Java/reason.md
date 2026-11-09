# Task B selection: 84_sales_csv_summary / Java

The source already parses fields[3] to an integer quantity before multiplication by parsed fields[4]. First notebook row therefore uses 10*200=2000, adds amount to region/day totals and quantity 10 to product totals. Date, region and product remain strings at fields 0,1,2. Parsing establishes numeric values and the int/Int declarations/inference enforce their subsequent numeric use.

Only row splitting, numeric conversions and the three aggregate updates are required. Input/report ranking and map initialization add no conversion or path distinction.

Selected complete source lines in `Main.java`: 26, 27, 28, 29, 30. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
