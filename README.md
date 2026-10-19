# Quidra Benchmark

## Purpose

This repository contains the data and instructions needed to benchmark the number of tokens an LLM would need to generate and understand programs written in different programming languages.

The benchmark measures two source-code-based quantities:
- Task A (Generation): output tokens, represented by the complete source code needed to satisfy a programming request.
- Task B (Understanding): input tokens, represented by the minimum source-code lines that must be read to answer a code-comprehension question or explain where and how the program would need to change for a proposed modification.

These are reproducible proxies for token usage, not measurements of complete LLM conversations. Natural-language prompts and explanations are not counted.

When the user asks you to "start the benchmark," follow the steps below.

## 1. Preparation and language selection

1. Clone this repository, or pull its latest changes if it is already available locally. Work on the `develop` branch.
2. Under `results/`, find the most recent directory named `YYYY-MM-DD`. Copy that directory and name the copy using today's date (`results/YYYY-MM-DD`). Work only in the new directory. If today's directory already exists, continue there without overwriting it.
3. Read `version.csv` in the working directory to identify the language versions used in the previous benchmark.
4. Check the latest stable release of each language against reliable, preferably official, sources. For Quidra, use the current `develop` branch of `quidra-lang/quidra` instead of a stable release.
5. Compare each current version with the version in `version.csv`. Identify languages whose relevant syntax has changed. For Quidra, check changes to `develop` even if its version number has not changed.
6. Before editing benchmark data, report to the user:
   - Each language with relevant syntax changes, and its previous and current versions.
   - Which languages you recommend benchmarking again, and why.
   - Any languages you recommend skipping because the syntax changes are too minor to affect the benchmark meaningfully.
7. Ask the user to select the languages to update in this run. Update the corresponding entries in `version.csv` only for the approved languages, then proceed.

Do not update an unapproved language merely because a newer version exists.

## 2. Benchmark execution

### 2.1. Dataset and tasks

Under `results/YYYY-MM-DD`, each programming language has three difficulty levels, with 100 programming topics per level. Each topic has two tasks:

**Task A — Generation (`taskA.txt`)**

`taskA.txt` describes a program to create. The corresponding source code is stored within that language's directory.

The source code must follow these rules:
- Use idiomatic, widely accepted conventions for the language. For example, do not add Python type annotations when they would not normally be used for that kind of program.
- When several implementations are reasonable, prefer one that is concise and conveys the required meaning clearly. Do not shorten code at the expense of important type information or clarity. For example, do not use C++ `auto` indiscriminately when an explicit type would better communicate the program's meaning.
- Preserve the intended behavior of the task.

**Task B — Understanding (`taskB.txt` and `list-up.txt`)**

`taskB.txt` describes a question about the program created for Task A. The question can involve either **code comprehension** (such as explaining an algorithm, tracing data, or identifying program behavior) or **modification analysis** (explaining which parts would need to change and how to satisfy proposed requirements).

Assume the existing program is bug-free. Task B does not implement the proposed modification or alter the Task A source code.

`list-up.txt` contains the smallest set of source-code lines that an LLM would need to read to accurately answer the question. Select these lines from the existing Task A program. Task B measures only the tokens in the selected source code; natural-language explanations and modified source code are not counted.

Rules for `list-up.txt`:
- **Minimal selection:** Include a line only when its omission would prevent an accurate answer based on the remaining selected lines. Avoid unnecessary context.
- **Exact extraction:** Copy complete lines exactly as written in the Task A source code. Do not rewrite, shorten, reformat, combine, or extract only part of a line.
- **Dependencies:** Include relevant declarations, types, operations, and dependencies whenever they are necessary to answer the question.
- **Modification analysis:** Include all source lines needed to identify and explain the required changes, including affected callers or dependent code when necessary. Do not include unaffected code unless it is required to understand the changes.
- **Order and uniqueness:** Include each selected line only once per source location. Group lines from the same file together, preserving their original order within that file. No particular order between files is required.
- **Scope:** Include only lines written for Task A. Do not include implementations of standard-library functions or external libraries. Do not add filenames, headings, or separators.
- **Consistency:** Apply the same selection criteria across all programming languages, regardless of their syntax or code structure.

### 2.2. Update affected programs

For each language approved in Step 1:

1. Identify only the topics whose existing Task A implementation needs to change because of syntax changes in the language's updated version, while still meeting the Task A writing rules above.
2. For each affected topic, make the minimum necessary changes to its source code and, where needed, its `list-up.txt` file. Ensure the Task B selection still accurately reflects the source lines required to answer a comprehension question or identify and understand a requested modification.
3. Leave all unaffected topics unchanged.

Building and executing programs is not required for this benchmark update. Nevertheless, review edited code for consistency with the target language version and the intended task behavior.

### 2.3. Recalculate token counts

For each language/topic updated in Step 2.2, use `metric/tokenizer.py` to recalculate:

- `taskA`: tokens in the complete Task A source code for that topic.
- `taskB`: tokens in that topic's `list-up.txt` file.

Save the token-colored HTML views as **`taskA.html`** and **`taskB.html`** alongside the corresponding language's source files. Run the following commands from the repository root, replacing the example directory and source filename with the actual paths:

```sh
LANG_DIR="results/YYYY-MM-DD/difficulty/topic/language"
python3 metric/tokenizer.py --html "$LANG_DIR/taskA.html" "$LANG_DIR/source.ext"
python3 metric/tokenizer.py --html "$LANG_DIR/taskB.html" "$LANG_DIR/list-up.txt"
```

For a Task A program consisting of multiple source files, pass all of its files to the same command and **sum the per-file token counts** printed to standard output. The HTML file will show all supplied files. `--html` sets the output path; if omitted, the default remains `token.html` in the current working directory.

Write both totals to the `tokens.csv` file in the corresponding topic directory, using this format:

```csv
taskA,27492
taskB,3749
```

Repeat this for every affected language/topic. Keep existing counts for unmodified topics only when the tokenizer rules are unchanged. **When the tokenizer changes, recalculate both tasks for all languages and topics before recomputing `score.md`**, so that counts from different counting rules are never mixed.

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
