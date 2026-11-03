# Task B selection: 43_run_length_encoding / C#

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

Regex (.)\1* groups adjacent identical characters; (\d+)([A-Z]) captures a whole decimal count and its letter. new string(char,count) builds the decoded run.

The array delimiters associate the constructed twelve-W target with values; the foreach opening connects that input to its encoded value and to decoding that encoded value.

Source: `Program.cs`. Selected original lines: 7,8,9,11,12,13,14,15,16. The following original-line dependencies support the answer above:

- L7: `string[] values =` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L8: `{` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L9: `    "AAABBBCCCD", new string('W', 12) + "B" + new string('W', 12) + "BBB", "ALGORITHM",` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `};` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L12: `foreach (string text in values)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L13: `{` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L14: `    string encoded = string.Concat(Regex.Matches(text, @"(.)\1*").Select(m => $"{m.Length}{m.Value[0]}"));` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L15: `    string decoded = Regex.Replace(encoded, @"(\d+)([A-Z])",` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L16: `        m => new string(m.Groups[2].Value[0], int.Parse(m.Groups[1].Value)));` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **202 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **317 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L7: 195 tokens (versus 202); removes `string[] values =`.
- Without L8: 200 tokens (versus 202); removes `{`.
- Without L9: 150 tokens (versus 202); removes `"AAABBBCCCD", new string('W', 12) + "B" + new string('W', 12) + "BBB", "ALGORITHM",`.
- Without L11: 199 tokens (versus 202); removes `};`.
- Without L12: 190 tokens (versus 202); removes `foreach (string text in values)`.
- Without L13: 200 tokens (versus 202); removes `{`.
- Without L14: 147 tokens (versus 202); removes `string encoded = string.Concat(Regex.Matches(text, @"(.)\1*").Select(m => $"{m.Length}{m.Value[0]}"));`.
- Without L15: 171 tokens (versus 202); removes `string decoded = Regex.Replace(encoded, @"(\d+)([A-Z])",`.
- Without L16: 164 tokens (versus 202); removes `m => new string(m.Groups[2].Value[0], int.Parse(m.Groups[1].Value)));`.
