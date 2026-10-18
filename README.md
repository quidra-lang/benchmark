# Quidra Benchmark

## Purpose

This repository contains the data and instructions needed to benchmark the number of tokens an LLM would need to generate and understand programs written in different programming languages.

The benchmark measures two source-code-based quantities:
- Task A (Generation): output tokens, represented by the complete source code needed to satisfy a programming request.
- Task B (Understanding): input tokens, represented by the minimum source-code lines that must be read to answer a code-comprehension question or determine how to make a requested code modification.

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

**Task A — Generation (`task1.txt`)**

`task1.txt` describes a program to create. The corresponding source code is stored within that language's directory.

The source code must follow these rules:
- Use idiomatic, widely accepted conventions for the language. For example, do not add Python type annotations when they would not normally be used for that kind of program.
- When several implementations are reasonable, prefer one that is concise and conveys the required meaning clearly. Do not shorten code at the expense of important type information or clarity. For example, do not use C++ `auto` indiscriminately when an explicit type would better communicate the program's meaning.
- Preserve the intended behavior of the task.

**Task B — Understanding (`task2.txt` and `list-up.txt`)**

`task2.txt` describes a question about the program created for Task A. The question can involve either **code comprehension** (such as explaining an algorithm, tracing data, or identifying program behavior) or **code modification** (such as finding where and how to implement a requested change). Assume the existing program is bug-free.

`list-up.txt` contains the smallest set of lines from the Task A source code that an LLM would need to read to accurately answer the comprehension question or identify and understand the requested modification. Task B measures the source code that must be read, not the tokens needed to write the answer or the modified code.

Rules for `list-up.txt`:
- Include all source lines necessary to answer the comprehension question or understand the requested modification, including relevant declarations or dependencies when needed.
- Include each required line only once, preferably in source order.
- Include only code written for Task A. Do not include the implementations of standard-library functions or external libraries.
- Do not include unrelated lines merely to provide additional context.

### 2.2. Update affected programs

For each language approved in Step 1:

1. Identify only the topics whose existing Task A implementation needs to change because of syntax changes in the language's updated version, while still meeting the Task A writing rules above.
2. For each affected topic, make the minimum necessary changes to its source code and, where needed, its `list-up.txt` file. Ensure the Task B selection still accurately reflects the source lines required to answer a comprehension question or identify and understand a requested modification.
3. Leave all unaffected topics unchanged.

Building and executing programs is not required for this benchmark update. Nevertheless, review edited code for consistency with the target language version and the intended task behavior.

### 2.3. Recalculate token counts

For each language/topic updated in Step 2.2, use `metric/tokenizer.py` to recalculate:

- `task1`: tokens in the complete Task A source code for that topic.
- `task2`: tokens in that topic's `list-up.txt` file.

Write both totals to the `tokens.csv` file in the corresponding topic directory, using this format:

```csv
task1,27492
task2,3749
```

Repeat this for every affected language/topic. Keep existing `tokens.csv` values for topics that were not modified; do not retokenize the entire dataset unnecessarily.

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