Normalize a decimal token "10" to integer 10 when constructing the current rolls collection, before scoring compares it with 10 or adds pin counts. The current entry point supplies numeric literals directly and performs no string-to-number ingestion conversion.

games holds integer literals and rolls aliases games[g]. Parse incoming decimal tokens with int.parse before constructing that integer list; the existing ==10 branch already expects numeric values.

The current roll literals/collection construction and numeric score comparisons locate ingestion conversion before scoring. A new textual parser is proposed in the answer but is not implemented or counted.
