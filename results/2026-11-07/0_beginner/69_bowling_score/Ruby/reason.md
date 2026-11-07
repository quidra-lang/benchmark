Normalize a decimal token "10" to integer 10 when constructing the current rolls collection, before scoring compares it with 10 or adds pin counts. The current entry point supplies numeric literals directly and performs no string-to-number ingestion conversion.

The numeric array enters rolls unchanged and the first comparison reads rolls[index]. Convert incoming tokens with Integer(token,10) at ingestion; frame logic remains unchanged.

The current roll literals/collection construction and numeric score comparisons locate ingestion conversion before scoring. A new textual parser is proposed in the answer but is not implemented or counted.
