The current row conversion already turns quantity "10" into exact integer 10 before multiplication and quantity aggregation. Date, region and product remain text keys; quantity*price produces a separately named sales amount, sent to total/region/day aggregates, while only quantity goes to product counts.

gmatch produces textual fields and tonumber converts fields 4 and 5; for these decimal integer spellings the resulting values are integers. Local does not statically enforce type. Date/region/product remain string fields.

CSV field conversion, quantity-price multiplication and each aggregation target establish numeric quantity and text keys. Report sorting/decoration do not influence those roles.
