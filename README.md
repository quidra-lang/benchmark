# Quidra Benchmark

Compare the source-code tokens needed to generate and understand programs across programming languages.

- **Task A — Generation:** tokens in the complete program required by `taskA.txt`.
- **Task B — Understanding:** the minimum tokens in complete source lines needed to answer `taskB.txt`.

Counts exclude prompts, answers, and selection rationales; they do not measure actual LLM API usage.

## Preparation

1. Run the benchmark only when the user explicitly requests execution (e.g., "Run the benchmark"). Discussion, review, or maintenance requests alone do not authorize a run.
2. Pull the latest `develop`. Limit file changes to the requested work and the benchmark outputs below.
3. Use the requested benchmark date, or today's date if none is specified. Continue in `results/YYYY-MM-DD` if it exists; otherwise copy the most recent earlier date directory.
4. Read that date's `version.csv`. For a new run, check official language updates and present the previous/current versions and proposed updates or skips to the user in chat. Obtain the user's explicit approval in chat before starting the benchmark; only then proceed with the approved languages, versions, and source revisions. Preserve those choices when resuming, and update only the corresponding entries in `version.csv`.
5. Within the approved scope, update only topics affected by language or task-requirement changes. Refresh their Task A sources, Task B selections and rationales, and token counts even if the language version is unchanged.

Each date contains three difficulty levels with 100 topics each. Task definitions are shared across languages; source files and measured outputs are stored in each topic's language directories.

## Task A

- Satisfy `taskA.txt`, including its restrictions, using idiomatic features, library APIs, and data structures for the selected language version.
- Prefer concise, clear code while preserving the required behavior and type guarantees. Do not impose declaration styles or implementation structures beyond the task requirements.
- Do not include source-code comments.

Review the source against the task and language version. Compiling, running, and testing Task A programs are not required; source review alone does not establish execution correctness.

## Task B

`taskB.txt` asks for code comprehension or an explanation of a proposed modification. Analyze the existing Task A source without implementing the modification.

For this analysis, assume Task A compiles, is bug-free, and satisfies its requirements. This is an evaluation assumption, not a claim of verified correctness; do not select extra code to investigate hypothetical bugs.

Create `list-up.txt` using these rules:

1. Define the same answer requirements for every language. Select enough source evidence to answer all of them using the excerpt and known language or documented library semantics. Task A's requirements alone are not source evidence.
2. Include only necessary declarations, operations, dependencies, and affected callers. Use guarantees such as types, mutation rules, and value semantics where available; inspect implementation lines only when those guarantees are insufficient. Apply this equally across languages.
3. Minimize the token count reported by `metric/tokenizer.py`, not the number of lines. Consider alternative excerpts that support the same answer with fewer tokens.
4. Copy complete source lines verbatim, preserving indentation and their order within each file. Group lines by source file without adding filenames, line numbers, headings, or separators.
5. Include each source location once. Identical lines from different locations may both be included when necessary.

Create `reason.md` alongside each excerpt. Explain how it answers every requirement, which language or library guarantees are used, and why the selected lines are necessary, including relevant alternatives considered.

Before finalizing, independently check that the excerpt alone supports every answer requirement and remove unnecessary lines. Do not rely on implementation details absent from the excerpt.

## Token counts

Run from the repository root, replacing the example paths:

```sh
LANG_DIR="results/YYYY-MM-DD/difficulty/topic/language"
python3 metric/tokenizer.py --json "$LANG_DIR/taskA.json" "$LANG_DIR/source.ext"
python3 metric/tokenizer.py --json "$LANG_DIR/taskB.json" "$LANG_DIR/list-up.txt"
```

For a multi-file program, pass all source files to the Task A command and sum the per-file counts printed to standard output. Save the two totals in `$LANG_DIR/tokens.csv`:

```csv
taskA,27492
taskB,3749
```

Generate `taskA.json` and `taskB.json` for each measured language/topic. Do not retain individual task HTML files.

## Results

1. Aggregate all `tokens.csv` files in the working date into `score.md`, preserving its existing metrics, normalization, weights, and structure. Do not add scope or focus breakdowns.
2. Commit and push the changes to `develop`, then verify that the remote branch contains them.
3. Report **Normalized token consumption** and **Total token consumption** to the user in chat, along with the updated languages/topics and skipped language updates.

## Viewer

[Open the token viewer](https://quidra-lang.github.io/benchmark/) and select a date, difficulty, topic, language, and task. Copy the resulting URL to share that view.

For a local preview, run from the repository root:

```sh
python3 metric/build_viewer.py
python3 -m http.server 8000 --bind 127.0.0.1
```

Open [http://localhost:8000/results/](http://localhost:8000/results/) through the server, rather than opening the HTML file directly.
