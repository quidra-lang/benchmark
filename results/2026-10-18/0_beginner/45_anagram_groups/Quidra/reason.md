# Task B selection: 45_anagram_groups / Quidra

## Common answer requirements

Locate the per-group filter while preserving group creation and the order of retained groups and words.

## Source evidence

The values iteration visits each grouped array in its existing order, and group.join emits that array as one line. Add a length-at-least-two guard at the per-group print site. Leave group creation and the iteration order intact.

## Minimization

The loop header is needed to show the filter applies once per group and preserves the order in which groups are visited. The unchanged signature and grouping computations are outside the change. Selected complete lines of `main.qui`: 7, 8.
