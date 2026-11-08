# Quidra Benchmark

## Purpose

This repository contains the data and instructions needed to benchmark the number of tokens an LLM would need to generate and understand programs written in different programming languages.

The benchmark measures two source-code-based quantities:
- Task A (Generation): output tokens, represented by the complete source code needed to satisfy a programming request.
- Task B (Understanding): input tokens, represented by the minimum source-code lines that must be read to answer a code-comprehension question or explain where and how the program would need to change for a proposed modification.

These are reproducible proxies for token usage, not measurements of complete LLM conversations. Natural-language prompts and explanations are not counted.

### Task requirements and understanding scope

Each Task A includes a topic-specific `Restriction:` section consistent with its programming requirements. Restrictions identify relevant values, variables, or local contracts without requiring a particular language's declaration syntax, helper-function structure, or call notation. Type inference and idiomatic standard-library APIs remain allowed. A represented value's type and a statically enforced type guarantee are distinct requirements; do not impose the latter unless a task explicitly requests it.

Task B samples a continuum of dependency scopes. The following five bands are sampling and reporting guides, not mutually exclusive kinds of programming work or a requirement to organize code into particular files or functions. Questions vary within each band and can combine a local fact with a wider dependency:

| Scope label | Intended extent of the question |
| --- | --- |
| `expression` | One value, expression, comparison, or immediate decision. |
| `block` | A short sequence of related operations or one local state transition. |
| `routine` | One logical operation from its inputs through its internal decisions to its result. |
| `interaction` | Related operations or processing stages and the dependency between them, within one feature. |
| `end_to_end` | A meaningful scenario from original input through central processing to observable output, including the necessary stages but not unrelated features. |

Each difficulty contains 20 questions in each band, giving 60 per band overall. These are declared sampling proportions, not estimates of real-work frequency. The scope describes the evidence actually needed by the whole question: appending one local clause to a broad question does not make the combined question local. For combined requirements, select the minimum source-line set sufficient for all of them together and count a shared source location once.

Assignments were fixed independently of language scores, using seed `20261107`, scheme `continuum-v2`, sorted difficulty/topic paths, and the following procedure. The sampling runtime was Python 3.12.14; this does not change any benchmarked language version. `RNG(label)` means Python's `random.Random` initialized with the big-endian integer represented by `SHA-256("20261107:<difficulty-directory>:<label>")`.

1. With `RNG("stratified-v1")`, shuffle a list containing 33 `local`, then 33 `broad`, then 33 `combined` pool labels, plus one extra `local` for Beginner, `broad` for Intermediate, and `combined` for Advanced. Assign the list to sorted topics. These pools are intermediate sampling strata, not the final scope labels.
2. With that same generator, shuffle the balanced focus pool described below and assign it to non-`broad` topics in sorted order.
3. With a fresh `RNG("continuum-v2")`, shuffle each topic pool in this order: `local`, `combined`, `broad`. From `local`, assign 20 topics to `expression` and the remainder to `block`. From `combined`, first fill `block` to 20, then assign 20 to `routine` and the rest to `interaction`. From `broad`, first fill `interaction` to 20 and assign the remaining 20 to `end_to_end`.
4. Apply the content-eligibility focus swap recorded below. Scope assignments remain unchanged. Record the final scope, applicable focus, seed and scheme in each `taskB.txt`. The question's comprehension/modification category remains a separate axis.

The ordered focus pool is `type_and_value_contract`, `name_and_call_resolution`, `initialization_and_defaults`, `boundaries_and_comparisons`, `indexing_and_iteration_order`, `numeric_units_and_rounding`, `output_representation`, `local_updates_and_mutation`, `parsing_and_normalization`, `empty_missing_and_errors`, `data_copy_and_aliasing`, and `short_circuit_and_control_flow`. Repeat this ordered pool six times, truncate to the number of non-`broad` topics, then shuffle as in Step 2. Thus type and call questions form a minority, alongside everyday value, formatting, parsing, boundary, update, ownership and control-flow work. A focus label does not authorize inventing new behavior or prescribing an implementation.

Content-eligibility adjustment: in Beginner, swap the focuses of `49_bracket_balance` and `64_spiral_matrix`. Bracket checking explicitly classifies bracket/nonbracket characters, making parsing applicable; spiral construction has no parser and instead explicitly requires fixed-width output. Bracket checking is the first output-focus topic in sorted order with applicable character parsing. This documented swap preserves the focus counts, avoids inventing work merely to fit a label, and does not depend on language implementations or scores.

All languages share the same task text and answer requirements. Task B answers must be supported by the selected source and known language/library semantics; a fact stated in Task A's restrictions is not source evidence by itself. When running the benchmark, first bring the approved languages' Task A implementations into conformance, then reselect and validate Task B excerpts and rationales, regenerate token views/counts, and aggregate fresh results. Regeneration is required by changed task definitions even when a language version has not changed. Retain the scope and applicable focus labels in each `taskB.txt` for analysis, but do not add scope- or focus-group breakdowns to `score.md`. Do not silently change weights after inspecting results.

When the user asks you to "start the benchmark," follow the steps below.

## File change restrictions

Do not add, edit, or delete any files other than those explicitly specified in this README.

The shared token viewer consists of `metric/tokenizer.py`, `metric/build_viewer.py`,
`metric/viewer.html`, `metric/viewer.js`, `metric/viewer.css`, `metric/views.json`,
`metric/test_viewer.py`, and `metric/test_viewer.cjs`. These files and this README
may be updated when maintaining the viewer. Generated task data is stored as
`taskA.json` and `taskB.json` in each language directory; individual task HTML
files must not be retained in benchmark results.

## 1. Preparation and language selection

1. Clone this repository, or pull its latest changes if it is already available locally. Work on the `develop` branch.
2. Use the benchmark date explicitly requested by the user when one is specified, including when resuming an existing run. Otherwise use today's date. Under `results/`, continue in that date's `YYYY-MM-DD` directory if it exists, without overwriting it. If it does not exist, copy the most recent earlier date directory and work in the new copy.
3. Read `version.csv` in the working directory to identify the language versions used in the previous benchmark.
4. Check the latest stable release of each language against reliable, preferably official, sources. For Quidra, use the current `develop` branch of `quidra-lang/quidra` instead of a stable release.
5. Compare each current version with the version in `version.csv`. Identify languages whose relevant syntax has changed. For Quidra, check changes to `develop` even if its version number has not changed.
6. Before editing benchmark data, report to the user:
   - Each language with relevant syntax changes, and its previous and current versions.
   - Which languages you recommend benchmarking again, and why.
   - Any languages you recommend skipping because the syntax changes are too minor to affect the benchmark meaningfully.
7. Ask the user to select the languages to update in this run unless the current run already has an approved selection. When resuming, preserve the approved languages and versions unless the user requests a change. Update the corresponding entries in `version.csv` only for the approved languages, then proceed.

Do not update an unapproved language merely because a newer version exists.

## 2. Benchmark execution

### 2.1. Dataset

Under `results/YYYY-MM-DD`, each programming language has three difficulty levels, with 100 programming topics per level. Each topic has two tasks: Task A (Generation) and Task B (Understanding).

### 2.2. Task A — Generation (`taskA.txt`)

`taskA.txt` describes a program to create. The corresponding source code is stored within that language's directory.

The source code must follow these rules:
- Follow idiomatic best practices appropriate to the language and the task, including the choice of language features, standard-library APIs, and data structures. For example, do not add Python type annotations when they would not normally be used for that kind of program.
- In Quidra, omit the type in a `:=` declaration when its initializer determines the intended static type. Write an explicit type when it supplies context, as in `nat count := 0`, `int32 count := 0` or `string[] names := []`, or preserves a stronger contract, such as keeping an error alternative in a union. Use `=` for assignment to an existing binding.
- In Quidra loop headers, use `for:` to declare a range variable or every written collection index; plain `for` reuses those variables. Each collection element independently uses `:=` to declare or `=` to reuse a binding. For example, `for: item := values[index]` declares both names, and `for: left := a[i], right := b[j]` declares both `nat` indices. Omit a range-variable type when its bounds determine the intended type; retain an explicit type when it supplies a different numeric context.
- When several implementations are reasonable, prefer one that is concise and conveys the required meaning clearly. Do not shorten code at the expense of important type information or clarity. For example, do not use C++ `auto` indiscriminately when an explicit type would better communicate the program's meaning.
- Preserve the intended behavior of the task.
- Do not write comments in the source code.

#### Review and testing

**Compiling, building, executing, or testing Task A programs is not required, either after initial creation or after updates.** Review the source code for consistency with the target language version and the intended task behavior. This review does not establish or imply that a program has actually been compiled, run, tested, or verified.

### 2.3. Task B — Understanding (`taskB.txt`, `list-up.txt`, and `reason.md`)

`taskB.txt` contains a question about the program created for Task A. Questions fall into two categories:
- **Code comprehension:** Explain an algorithm, trace data, or identify program behavior or side effects.
- **Modification analysis:** Explain which parts would need to change and how to satisfy proposed new requirements.

Task B does not implement modifications or alter the Task A source code.

#### Assumptions

For **Task B analysis only**, treat every Task A program **as if** it compiles successfully, is bug-free, and satisfies all Task A requirements. **This is an assumption for evaluating code understanding, not a guarantee or a claim that compilation, execution, or correctness has actually been checked.**

- There is no need to verify build success, implementation correctness, potential bugs, or compliance with Task A requirements.
- Do not read additional source code solely to investigate hypothetical bugs or implementations that would contradict these assumptions.
- The language specification and known semantics of its standard library may be used as prior knowledge when understanding the program.

#### Purpose of `list-up.txt`

`list-up.txt` contains the set of complete lines from the Task A source code with the **minimum token count necessary** for an LLM to answer the Task B question accurately.

The answer must be derivable from the selected source code together with the language specification and known standard-library semantics. Do not omit source evidence that is required to understand the program merely because Task A requirements describe the intended behavior.

Task B counts only tokens in the selected source code. The question, natural-language answer, modified source code, and selection rationale are excluded from the token count.

#### Selection rules for `list-up.txt`

1. **Information necessary to answer the question**

   Select only lines that contain information necessary to answer the question accurately.

   Include relevant declarations, types, branches, operations, data dependencies, and call relationships when needed.

   Exclude code that is unrelated to the answer or merely provides extra context.

2. **Use guarantees of the programming language**

   Facts guaranteed by static typing, mutation authority, value semantics, control flow, or other language rules may be inferred directly from those guarantees.

   When declarations, types, or call syntax establish a fact needed for the answer, do not include a function's implementation merely to reconfirm that fact.

   Do not assume properties that the language does not guarantee. If necessary behavior or side effects cannot be established, inspect the relevant implementation.

   Apply these principles equally to all programming languages.

3. **Trace dependencies only as needed**

   Include a called function's implementation only when the already selected code and available language semantics are insufficient to answer the question accurately.

   Even when a called implementation is necessary, select only the lines required for the answer; do not automatically include the entire function.

   Use the documented semantics of standard and external libraries without including their implementation source code.

4. **Modification analysis**

   Select lines sufficient to identify the changes needed for the proposed requirement and explain how to make them.

   Include affected callers or dependent processing when they are necessary to explain the changes.

   Do not include unaffected code that is unnecessary to understand the proposed change.

   Do not produce modified source code.

5. **Minimum token count**

   When several line sets permit an accurate answer, choose the set with the lowest token count.

   Do not stop after removing unnecessary lines from a single candidate. Consider alternative sets of lines that convey the same necessary information using fewer tokens.

   Minimize the token count reported by `metric/tokenizer.py`, not the number of source lines.

6. **Preserve the original code**

   Copy complete lines verbatim from the Task A source code.

   Do not extract part of a line, abbreviate, rewrite, reformat, or combine lines.

   Preserve their original text and indentation.

7. **Order and uniqueness**

   Include each selected source line only once per source location.

   Preserve the original order of selected lines within each source file.

   For a program with multiple files, group selected lines from the same file together. No specific order between files is required.

   If identical lines occur at different source locations and both are necessary, include both.

   Do not add filenames, line numbers, headings, or separators to `list-up.txt`.

8. **Fairness across languages**

   Use the same answer requirements and selection criteria for every programming language.

   Different required source lines due to language-specific syntax, types, or semantics are acceptable.

   Do not change the criteria for deciding whether a line is necessary to favor or disadvantage a particular language.

#### Selection rationale (`reason.md`)

For every `list-up.txt`, create a `reason.md` in the same directory to record why the source-code lines were selected.

- Identify the Task B answer requirements and explain how the selected lines support each requirement.
- Explain any language guarantees or documented library semantics used to avoid including additional implementation lines.
- Explain how the selection was minimized, including why selected lines are necessary and any relevant alternative line sets considered.

`reason.md` is an explanation of the selection, not part of the source-code excerpt. Its contents are excluded from the Task B token count.

#### Validate the selection

Before finalizing `list-up.txt`:

1. Break the Task B question into individual answer requirements. Define a common set of requirements before selecting excerpts for individual languages.
2. Verify that every requirement can be answered accurately using only the selected source code and the language specification and known standard-library semantics.
3. Review each selected line and remove it if doing so does not lose information necessary for the answer.
4. Consider whether a different set of lines can support the same answer with fewer tokens.
5. Independently verify that the final excerpt alone supports a correct explanation of every required fact.

During independent validation, do not use Task A implementation details absent from the excerpt. The stated assumptions, language specification, and known standard-library semantics remain available.

**The Task B metric is the minimum number of source-code tokens needed to answer the question accurately.**

### 2.4. Update affected programs

For each language approved in Step 1:

1. Identify only the topics whose existing Task A implementation needs to change because of syntax changes in the language's updated version, while still meeting the Task A writing rules above.
2. For each affected topic, make the minimum necessary changes to its source code and, where needed, its `list-up.txt` and `reason.md` files. Ensure the Task B selection still accurately reflects the source lines required to answer a comprehension question or identify and understand a requested modification, and keep the recorded rationale consistent with that selection.
3. Leave all unaffected topics unchanged.

**Building, running, and testing updated Task A programs are not required.** Review edited code for consistency with the target language version and the intended task behavior, without presenting that review as proof of compilation or correctness.

### 2.5. Recalculate token counts

For each language/topic updated in Step 2.4, use `metric/tokenizer.py` to recalculate:

- `taskA`: tokens in the complete Task A source code for that topic.
- `taskB`: tokens in that topic's `list-up.txt` file.

Save the token-view data as **`taskA.json`** and **`taskB.json`** alongside the corresponding language's source files. Run the following commands from the repository root, replacing the example directory and source filename with the actual paths:

```sh
LANG_DIR="results/YYYY-MM-DD/difficulty/topic/language"
python3 metric/tokenizer.py --json "$LANG_DIR/taskA.json" "$LANG_DIR/source.ext"
python3 metric/tokenizer.py --json "$LANG_DIR/taskB.json" "$LANG_DIR/list-up.txt"
```

For a Task A program consisting of multiple source files, pass all of its files to the same command and **sum the per-file token counts** printed to standard output. The viewer shows all supplied files in argument order. `--json` sets the output path; if omitted, the default is `token.json` in the current working directory. Python uses the same tokenizer for counts and saved boundaries; viewing never re-tokenizes the source or executes Python.

Do not save individual `taskA.html` or `taskB.html` files in benchmark results. All task views use the shared viewer. An explicit `--html PATH` export remains available for an occasional self-contained file that can be opened directly without a web server.

Write both totals to the `tokens.csv` file in the corresponding **language directory** (`$LANG_DIR/tokens.csv`), using this format:

```csv
taskA,27492
taskB,3749
```

Repeat this for every affected language/topic.

After adding or removing task JSON files, rebuild the shared selection index:

```sh
python3 metric/build_viewer.py
```

#### View token-colored code

The shared `metric/viewer.html` loads the small `metric/views.json` selection index,
then fetches only the selected task's JSON. The JSON stores normalized source text
and token lengths instead of repeating HTML tags. Line numbers, token colors, blank
lines, and separate source-file blocks are reconstructed by `metric/viewer.js`.
No external JavaScript libraries, Python runtime, or application backend are needed
in the browser.

Serve the repository root with any static web server, for example:

```sh
python3 -m http.server 8000 --bind 127.0.0.1
```

Open [the shared viewer](http://localhost:8000/metric/viewer.html) and select a date,
difficulty, topic, language, and task. The address updates to a shareable link for
the selected view. For a standalone data file, use
`http://localhost:8000/metric/viewer.html?view=token.json`, where `view` is a path
relative to the repository root. The same files can be served by GitHub Pages or
another static host; keep `metric/` and `results/` at their existing relative paths.
Opening `viewer.html` with a `file://` URL does not permit automatic JSON fetches.

Run tooling regression tests with
`python3 -m unittest discover -s metric -p 'test_*.py'`.
For browser integration tests, install the development-only `playwright` Node
package and its Chromium browser, then run `node metric/test_viewer.cjs`.
An existing Chromium executable can be selected with `CHROMIUM_PATH`.

## 3. Aggregate results

Read every `tokens.csv` file across all languages, difficulty levels, and topics in the working date directory.

Recalculate and update every applicable value in `results/YYYY-MM-DD/score.md`, using the same aggregation and normalization rules already defined by the benchmark. Preserve the existing score structure and metric definitions.

## 4. Report results

**First, commit all benchmark updates and push them to the `develop` branch of `quidra-lang/benchmark` (`origin/develop`).** Verify that the push succeeded and that the remote branch contains the final changes. Do not push to `main`.

Report the updated results to the user, including both of these metrics (using these exact names):

- **Normalized token consumption**
- **Total token consumption**

Also identify which languages and topics were updated, and which language updates were skipped. Make clear that the values reflect the benchmark's source-code token measures, not total tokens billed by an actual LLM API.

The benchmark run is complete once the results have been updated, pushed to `develop`, and reported.
