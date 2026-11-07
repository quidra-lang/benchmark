The final `printf` supplies octal and uppercase hexadecimal from the same original n. Replace only `%X` with `%x`; standard printf conversion gives lowercase, no base prefix without `#`, and no leading zeros without a width/precision. 43981 becomes `hex=abcd`; zero stays `hex=0`. The preceding decimal/binary emission remains unchanged. The retained output boundary shows the case change belongs solely to the hex field.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
