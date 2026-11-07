Use `std::nouppercase` instead of the uppercase manipulator at the hexadecimal insertion; 43981 becomes `hex=abcd`. The stream defaults and absence of showbase/width preserve no prefix and no leading zeros; zero stays `hex=0`. Decimal is reset explicitly for the initial field, binary uses the independently trimmed bit string, and octal is inserted before hex, so those stages need no conversion changes.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
