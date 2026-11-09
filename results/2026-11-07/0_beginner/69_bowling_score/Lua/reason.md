Normalize a decimal token "10" to integer 10 when constructing the current rolls collection, before scoring compares it with 10 or adds pin counts. The current entry point supplies numeric literals directly and performs no string-to-number ingestion conversion.

The numeric table becomes rolls and is compared with integer 10. Use tonumber(token,10) before storing a received decimal roll; relying on arithmetic coercion would not fix string-vs-number equality.

The current roll literals/collection construction and numeric score comparisons locate ingestion conversion before scoring. A new textual parser is proposed in the answer but is not implemented or counted.
