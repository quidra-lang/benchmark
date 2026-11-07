The current row conversion already turns quantity "10" into exact integer 10 before multiplication and quantity aggregation. Date, region and product remain text keys; quantity*price produces a separately named sales amount, sent to total/region/day aggregates, while only quantity goes to product counts.

int.parse(f[3]) has int return type, so inferred quantity is statically int after runtime parsing; price is also parsed before multiplication. f[0..2] stay String keys and the two numeric update paths are explicit.

CSV field conversion, quantity-price multiplication and each aggregation target establish numeric quantity and text keys. Report sorting/decoration do not influence those roles.
