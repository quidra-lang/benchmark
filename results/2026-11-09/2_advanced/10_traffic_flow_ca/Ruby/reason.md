Answer requirements: Identify the CLASS stop-token conversion, its stored yes/no result for CLASS BUS 3 5 N Y, and whether the parser case-normalizes the token.

Ruby evidence and answer: This parser retains stop as the original 'Y'/'N' string in ClassInfo.stop: stop: stop is the storage operation. CLASS BUS 3 5 N Y stores stop='Y' independently of overtake='N'. The later heading_for_stop? decision compares @kind.stop == 'Y'. There is no Boolean conversion inside this parser, so it would be inaccurate to invent one. line.split and direct field storage preserve case; the later comparison is case-sensitive.

Semantics: String splitting and slicing retain character case. Exact string equality (J match -:, C strcmp, Zig std.mem.eql through S.eq) supplies a Boolean; positional constructors bind that last argument to the shown stop field. Ruby instead retains the flag spelling as explained above.

Selection review: The excerpt was read again independently of the surrounding implementation. It supplies the operands, the decision and the affected operation needed above. Full input processing, unrelated branches and output operations do not establish any additional required conclusion. Adding routine bodies or callers beyond this boundary was considered and rejected because their internals are not needed under the Task A correctness assumption. Complete source lines prevent shortening a dense line; necessary bindings are retained where the expression alone would leave their meaning unresolved. Blank lines and duplicate source locations are excluded. The selected excerpt contains 177 tokenizer tokens. No proposed modification was implemented.

## Task A source conformity review

Remove Ruby magic comment to meet no-source-comments rule; explicit freeze operations remain. No literal-freeze introspection or required literal-string identity was found; intended file outputs are unchanged by source review. Source line counts were preserved for excerpt provenance. The current excerpt contains 177 tokens; edited Task A sources were remeasured. These are source-review corrections, not a claim of compilation or execution verification.
