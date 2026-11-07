Food subtotals are milk 396, bread 248, apple 512, eggs 268, totaling 1424 yen. Category tax truncates 1424*8/100 to 113; truncating those item-subtotal taxes first would give 31+19+40+21=111. General subtotal 932 gives tax 93, so the final payment is 1424+932+113+93=2562, with each base amount and tax included once.

The boolean category maps food to totals[0]; ~/100 truncates after full aggregation. The final expression adds both category bases and both integer taxes once.

Item quantity/price/category, category aggregation, integer tax division and total payment are required to distinguish category tax 113 from itemwise tax 111. Other receipt decoration is omitted.
