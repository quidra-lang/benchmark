The existing entry point stores numeric int pin counts directly, so it performs no decimal-string conversion. For string token "10", parse base-10 integer at ingestion and store/pass that value into the existing numeric roll collection before strike comparisons or score addition. Use strtol with base 10 and a checked result, then convert to int. Parsing the whole token is necessary; subtracting character zero would produce only one digit. Frame rules remain unchanged.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
