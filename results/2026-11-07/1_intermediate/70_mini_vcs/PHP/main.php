<?php
class VcsError extends Exception {}

class Commit
{
    public function __construct(
        public string $id,
        public int $sequence,
        public array $parents,
        public array $tree,
        public string $message
    ) {}
}

class MiniVcs
{
    private array $commits = [];
    private int $nextSequence = 0;
    private array $branches;
    private array $tags = [];
    private ?string $branch = 'main';
    private ?Commit $detached = null;
    private array $work = [];
    private array $index = [];
    private array $conflicts = [];
    private ?array $operation = null;
    private array $stash = [];
    private array $ignores = [];

    public function __construct()
    {
        $this->branches = ['main' => $this->create([], [], 'init')];
    }

    private function head(): Commit
    {
        return $this->branch !== null ? $this->branches[$this->branch] : $this->detached;
    }

    private function moveHead(Commit $commit): void
    {
        if ($this->branch !== null) {
            $this->branches[$this->branch] = $commit;
        } else {
            $this->detached = $commit;
        }
    }

    private function paths(array ...$trees): array
    {
        $paths = [];
        foreach ($trees as $tree) {
            foreach ($tree as $path => $_) {
                $paths[$path] = true;
            }
        }
        $result = array_map('strval', array_keys($paths));
        sort($result, SORT_STRING);
        return $result;
    }

    private function differences(array $a, array $b): array
    {
        return array_values(array_filter($this->paths($a, $b),
            fn($p) => ($a[$p] ?? null) !== ($b[$p] ?? null)));
    }

    private function equalTrees(array $a, array $b): bool
    {
        return !$this->differences($a, $b);
    }

    private function matchPath(array &$destination, array $source, string $path): void
    {
        if (isset($source[$path])) {
            $destination[$path] = $source[$path];
        } else {
            unset($destination[$path]);
        }
    }

    private function create(array $parents, array $tree, string $message): Commit
    {
        $text = "commit {$this->nextSequence}\n";
        foreach ($parents as $parent) {
            $text .= "parent {$parent->id}\n";
        }
        foreach ($this->paths($tree) as $path) {
            $text .= "file $path {$tree[$path]}\n";
        }
        $text .= "message $message\n";
        $hash = 0;
        for ($i = 0; $i < strlen($text); $i++) {
            $hash = ($hash * 131 + ord($text[$i])) % 2147483647;
        }
        $commit = new Commit(sprintf('%08x', $hash), $this->nextSequence++, $parents, $tree, $message);
        $this->commits[$commit->id] = $commit;
        return $commit;
    }

    private function record(array $parents, array $tree, string $message): void
    {
        $old = $parents[0]->tree;
        $added = 0;
        $modified = 0;
        $deleted = 0;
        foreach ($this->differences($old, $tree) as $path) {
            if (!isset($old[$path])) {
                $added++;
            } elseif (!isset($tree[$path])) {
                $deleted++;
            } else {
                $modified++;
            }
        }
        $commit = $this->create($parents, $tree, $message);
        $this->moveHead($commit);
        $location = $this->branch ?? 'detached HEAD';
        echo "[$location {$commit->id}] $message ($added added, $modified modified, $deleted deleted)\n";
    }

    private function resolve(string $revision): Commit
    {
        $parts = explode('~', $revision);
        $anchor = $parts[0];
        $commit = $anchor === 'HEAD' ? $this->head() :
            ($this->branches[$anchor] ?? $this->tags[$anchor] ?? $this->commits[$anchor] ?? null);
        for ($i = 0; $i < (int)($parts[1] ?? 0); $i++) {
            $commit = $commit?->parents[0] ?? null;
        }
        if ($commit === null) {
            throw new VcsError("unknown revision '$revision'");
        }
        return $commit;
    }

    private function distances(Commit $commit): array
    {
        $distances = [$commit->id => 0];
        $queue = [$commit];
        for ($i = 0; $i < count($queue); $i++) {
            $current = $queue[$i];
            foreach ($current->parents as $parent) {
                if (!isset($distances[$parent->id])) {
                    $distances[$parent->id] = $distances[$current->id] + 1;
                    $queue[] = $parent;
                }
            }
        }
        return $distances;
    }

    private function ancestor(Commit $ancestor, Commit $descendant): bool
    {
        return isset($this->distances($descendant)[$ancestor->id]);
    }

    private function mergeBase(Commit $a, Commit $b): Commit
    {
        $da = $this->distances($a);
        $db = $this->distances($b);
        $common = array_intersect_key($da, $db);
        $best = null;
        $bestDistance = PHP_INT_MAX;
        foreach ($common as $id => $_) {
            $candidate = $this->commits[$id];
            foreach ($common as $other => $_) {
                if ($id !== $other && $this->ancestor($candidate, $this->commits[$other])) {
                    continue 2;
                }
            }
            $distance = max($da[$id], $db[$id]);
            if ($best === null || $distance < $bestDistance ||
                ($distance === $bestDistance && $candidate->sequence > $best->sequence)) {
                $best = $candidate;
                $bestDistance = $distance;
            }
        }
        return $best;
    }

    private function summary(Commit $commit): string
    {
        $refs = [];
        if ($this->head() === $commit) {
            $refs[] = $this->branch !== null ? "HEAD -> {$this->branch}" : 'HEAD';
        }
        foreach ($this->paths($this->branches) as $name) {
            if ($this->branches[$name] === $commit && $name !== $this->branch) {
                $refs[] = $name;
            }
        }
        foreach ($this->paths($this->tags) as $name) {
            if ($this->tags[$name] === $commit) {
                $refs[] = "tag: $name";
            }
        }
        return $commit->id . ($refs ? ' (' . implode(', ', $refs) . ')' : '') . " {$commit->message}";
    }

    private function changes(array $a, array $b): void
    {
        $changed = $this->differences($a, $b);
        if (!$changed) {
            echo "(no changes)\n";
        }
        foreach ($changed as $path) {
            if (!isset($a[$path])) {
                echo "A $path: {$b[$path]}\n";
            } elseif (!isset($b[$path])) {
                echo "D $path: {$a[$path]}\n";
            } else {
                echo "M $path: {$a[$path]} -> {$b[$path]}\n";
            }
        }
    }

    private function checkProgress(): void
    {
        if ($this->operation !== null) {
            throw new VcsError("{$this->operation[0]} in progress");
        }
    }

    private function uncommitted(): bool
    {
        if (!$this->equalTrees($this->index, $this->head()->tree)) {
            return true;
        }
        foreach ($this->index as $path => $value) {
            if (($this->work[$path] ?? null) !== $value) {
                return true;
            }
        }
        return false;
    }

    private function checkUncommitted(): void
    {
        if ($this->uncommitted()) {
            throw new VcsError('uncommitted changes');
        }
    }

    private function checkOverwrite(array $selected): void
    {
        $selected = array_unique($selected);
        sort($selected, SORT_STRING);
        $head = $this->head()->tree;
        foreach ($selected as $path) {
            if (($this->index[$path] ?? null) !== ($head[$path] ?? null) ||
                ($this->work[$path] ?? null) !== ($head[$path] ?? null)) {
                throw new VcsError("local changes to '$path' would be overwritten");
            }
        }
    }

    private function switchTree(array $tree): void
    {
        $changed = $this->differences($this->head()->tree, $tree);
        $this->checkOverwrite($changed);
        foreach ($changed as $path) {
            $this->matchPath($this->index, $tree, $path);
            $this->matchPath($this->work, $tree, $path);
        }
    }

    private function mergeTrees(array $base, array $ours, array $theirs): array
    {
        $result = [];
        $conflicts = [];
        $markers = [];
        foreach ($this->paths($base, $ours, $theirs) as $path) {
            $b = $base[$path] ?? null;
            $o = $ours[$path] ?? null;
            $t = $theirs[$path] ?? null;
            if ($t === $b || $o === $t) {
                $this->matchPath($result, $ours, $path);
            } elseif ($o === $b) {
                $this->matchPath($result, $theirs, $path);
            } else {
                $conflicts[] = $path;
                $this->matchPath($result, $ours, $path);
                $markers[$path] = '<<<<<<< ' . ($o ?? '(deleted)') . ' ======= ' . ($t ?? '(deleted)') . ' >>>>>>>';
            }
        }
        return [$result, $conflicts, $markers];
    }

    private function apply(array $base, array $theirs, string $kind, Commit $target,
                           string $message, array $parents, ?Commit $mergeBase = null): void
    {
        [$result, $conflicts, $markers] = $this->mergeTrees($base, $this->head()->tree, $theirs);
        $changed = $this->differences($this->head()->tree, $result);
        $this->checkOverwrite(array_merge($changed, $conflicts));
        if ($kind === 'merge') {
            echo "Merge base {$mergeBase->id}\n";
        }
        if ($kind !== 'merge' && !$conflicts && $this->equalTrees($result, $this->head()->tree)) {
            echo "nothing to commit\n";
            return;
        }
        foreach ($changed as $path) {
            $this->matchPath($this->index, $result, $path);
            $this->matchPath($this->work, $result, $path);
        }
        if (!$conflicts) {
            $this->record($parents, $result, $message);
            return;
        }
        foreach ($conflicts as $path) {
            $this->work[$path] = $markers[$path];
            echo "CONFLICT $path\n";
        }
        $this->conflicts = $conflicts;
        $this->operation = [$kind, $target];
        echo match ($kind) {
            'merge' => 'Automatic merge failed; fix conflicts and then commit the result.',
            'revert' => "error: could not revert {$target->id}",
            default => "error: could not apply {$target->id}"
        }, "\n";
    }

    private function ignored(string $path): bool
    {
        if (isset($this->index[$path]) || in_array($path, $this->conflicts, true)) {
            return false;
        }
        foreach ($this->ignores as $pattern) {
            if (preg_match($pattern, $path)) {
                return true;
            }
        }
        return false;
    }

    private function pathspec(string $path): never
    {
        throw new VcsError("pathspec '$path' did not match any files");
    }

    private function missingPath(string $path, string $revision): never
    {
        throw new VcsError("path '$path' does not exist in '$revision'");
    }

    private function headReport(): void
    {
        $head = $this->head();
        echo "HEAD is now at {$head->id} {$head->message}\n";
    }

    private function status(): void
    {
        $head = $this->head();
        echo $this->branch !== null ? "On branch {$this->branch}\n" : "HEAD detached at {$head->id}\n";
        if ($this->operation !== null) {
            $labels = ['merge' => 'Merging', 'revert' => 'Reverting', 'cherry-pick' => 'Cherry-picking'];
            echo "{$labels[$this->operation[0]]} {$this->operation[1]->id}\n";
        }
        $lines = [];
        $selected = array_unique(array_merge($this->paths($head->tree, $this->index, $this->work), $this->conflicts));
        sort($selected, SORT_STRING);
        foreach ($selected as $path) {
            if (in_array($path, $this->conflicts, true)) {
                $lines[] = "UU $path";
            } elseif (isset($this->index[$path])) {
                $x = !isset($head->tree[$path]) ? 'A' : ($head->tree[$path] !== $this->index[$path] ? 'M' : '.');
                $y = !isset($this->work[$path]) ? 'D' : ($this->work[$path] !== $this->index[$path] ? 'M' : '.');
                if ($x !== '.' || $y !== '.') {
                    $lines[] = "$x$y $path";
                }
            } else {
                if (isset($head->tree[$path])) {
                    $lines[] = "D. $path";
                }
                if (isset($this->work[$path]) && !$this->ignored($path)) {
                    $lines[] = "?? $path";
                }
            }
        }
        echo implode("\n", $lines ?: ['nothing to commit, working tree clean']), "\n";
    }

    private function rebase(Commit $target): void
    {
        $this->checkProgress();
        if ($this->ancestor($target, $this->head())) {
            echo "Already up to date\n";
            return;
        }
        $this->checkUncommitted();
        $list = [];
        $current = $this->head();
        while (!$this->ancestor($current, $target)) {
            $list[] = $current;
            $current = $current->parents[0];
        }
        $list = array_reverse($list);
        $tree = $target->tree;
        $actions = [];
        foreach ($list as $old) {
            [$result, $conflicts] = $this->mergeTrees($old->parents[0]->tree, $tree, $old->tree);
            if ($conflicts) {
                throw new VcsError("could not rebase {$old->id}: conflict in '{$conflicts[0]}'");
            }
            if ($this->equalTrees($result, $tree)) {
                $actions[] = [$old, null];
            } else {
                $tree = $result;
                $actions[] = [$old, $result];
            }
        }
        $this->switchTree($tree);
        foreach ($actions as [$old, $result]) {
            if ($result !== null) {
                $fresh = $this->create([$target], $result, $old->message);
                echo "pick {$old->id} -> {$fresh->id} {$old->message}\n";
                $target = $fresh;
            } else {
                echo "skip {$old->id} {$old->message}\n";
            }
        }
        $this->moveHead($target);
        $this->headReport();
    }

    private function stashCommand(?string $action): void
    {
        if ($action === 'LIST') {
            if (!$this->stash) {
                echo "(no stash entries)\n";
            }
            foreach ($this->stash as $i => $entry) {
                echo "stash@{{$i}}: {$entry[0]}\n";
            }
        } elseif ($action === 'DROP') {
            if (!$this->stash) {
                throw new VcsError('no stash entries');
            }
            $entry = array_shift($this->stash);
            echo "Dropped stash@{0}: {$entry[0]}\n";
        } elseif ($action === 'POP') {
            if (!$this->stash) {
                throw new VcsError('no stash entries');
            }
            $this->checkProgress();
            $this->checkUncommitted();
            [$label, $base, $saved] = $this->stash[0];
            [$result, $conflicts] = $this->mergeTrees($base->tree, $this->head()->tree, $saved);
            if ($conflicts) {
                throw new VcsError("stash conflict in '{$conflicts[0]}'");
            }
            $changed = $this->differences($this->head()->tree, $result);
            $this->checkOverwrite($changed);
            foreach ($changed as $path) {
                $this->matchPath($this->work, $result, $path);
            }
            array_shift($this->stash);
            echo "Restored stash@{0}: $label\n";
            $this->changes($this->head()->tree, $result);
        } else {
            $this->checkProgress();
            if (!$this->uncommitted()) {
                echo "No local changes to save\n";
                return;
            }
            $head = $this->head();
            $selected = $this->paths($this->index, $head->tree);
            $saved = [];
            foreach ($selected as $path) {
                $this->matchPath($saved, $this->work, $path);
                $this->matchPath($this->work, $head->tree, $path);
            }
            $this->index = $head->tree;
            $location = $this->branch ?? '(no branch)';
            $label = "WIP on $location: {$head->id} {$head->message}";
            array_unshift($this->stash, [$label, $head, $saved]);
            echo "Saved stash@{0}: $label\n";
        }
    }

    private function reachable(array $roots): array
    {
        $live = [];
        foreach ($roots as $root) {
            $live += $this->distances($root);
        }
        return $live;
    }

    private function graph(): void
    {
        $live = $this->reachable(array_merge([$this->head()], array_values($this->branches), array_values($this->tags)));
        $ordered = array_values(array_intersect_key($this->commits, $live));
        usort($ordered, fn($a, $b) => $b->sequence <=> $a->sequence);
        $lanes = [];
        foreach ($ordered as $commit) {
            if (!in_array($commit, $lanes, true)) {
                $lanes[] = $commit;
            }
            $first = array_search($commit, $lanes, true);
            $symbols = [];
            foreach ($lanes as $i => $lane) {
                $symbols[] = $lane === $commit ? ($i === $first ? '*' : '/') : '|';
            }
            echo implode(' ', $symbols), ' ', $this->summary($commit), "\n";
            $kept = [];
            foreach ($lanes as $i => $lane) {
                if ($lane !== $commit || $i === $first) {
                    $kept[] = $lane;
                }
            }
            $lanes = $kept;
            if (!$commit->parents) {
                array_splice($lanes, $first, 1);
            } else {
                $lanes[$first] = $commit->parents[0];
                $second = $commit->parents[1] ?? null;
                if ($second !== null && !in_array($second, $lanes, true)) {
                    array_splice($lanes, $first + 1, 0, [$second]);
                }
            }
        }
    }

    public function execute(string $line): void
    {
        [$command, $rest] = array_pad(explode(' ', $line, 2), 2, '');
        $args = $rest === '' ? [] : explode(' ', $rest);
        $path = $args[0] ?? null;
        try {
            switch ($command) {
                case 'WRITE':
                    [$path, $text] = explode(' ', $rest, 2);
                    $this->work[$path] = $text;
                    break;
                case 'REMOVE':
                    if (!isset($this->work[$path])) {
                        throw new VcsError("no such file '$path'");
                    }
                    unset($this->work[$path]);
                    break;
                case 'ADD':
                    if ($path === 'ALL') {
                        $selected = array_filter($this->paths($this->work, $this->index), fn($p) => !$this->ignored($p));
                        foreach ($selected as $p) {
                            $this->matchPath($this->index, $this->work, $p);
                        }
                        $this->conflicts = [];
                    } else {
                        if (isset($this->work[$path]) && $this->ignored($path)) {
                            throw new VcsError("path '$path' is ignored");
                        }
                        if (!isset($this->work[$path]) && !isset($this->index[$path]) && !in_array($path, $this->conflicts, true)) {
                            $this->pathspec($path);
                        }
                        $this->matchPath($this->index, $this->work, $path);
                        $this->conflicts = array_values(array_diff($this->conflicts, [$path]));
                    }
                    break;
                case 'RM':
                    if (!isset($this->index[$path])) {
                        $this->pathspec($path);
                    }
                    unset($this->index[$path], $this->work[$path]);
                    $this->conflicts = array_values(array_diff($this->conflicts, [$path]));
                    break;
                case 'UNSTAGE':
                    if (!isset($this->index[$path]) && !isset($this->head()->tree[$path])) {
                        $this->pathspec($path);
                    }
                    $this->matchPath($this->index, $this->head()->tree, $path);
                    break;
                case 'RESTORE':
                    if (count($args) === 1) {
                        if (!isset($this->index[$path])) {
                            $this->pathspec($path);
                        }
                        $this->work[$path] = $this->index[$path];
                    } else {
                        $tree = $this->resolve($args[1])->tree;
                        if (!isset($tree[$path])) {
                            $this->missingPath($path, $args[1]);
                        }
                        $this->index[$path] = $tree[$path];
                        $this->work[$path] = $tree[$path];
                        $this->conflicts = array_values(array_diff($this->conflicts, [$path]));
                    }
                    break;
                case 'IGNORE':
                    $pattern = str_replace(['\\*', '\\?'], ['.*', '.'], preg_quote($path, '~'));
                    $this->ignores[] = '~\A' . $pattern . '\z~';
                    break;
                case 'COMMIT':
                    if ($this->conflicts) {
                        throw new VcsError('unresolved conflicts');
                    }
                    if ($this->operation !== null && $this->operation[0] === 'merge') {
                        $this->record([$this->head(), $this->operation[1]], $this->index, $rest);
                        $this->operation = null;
                    } elseif ($this->equalTrees($this->index, $this->head()->tree)) {
                        echo "nothing to commit\n";
                    } else {
                        $this->record([$this->head()], $this->index, $rest);
                        $this->operation = null;
                    }
                    break;
                case 'AMEND':
                    $this->checkProgress();
                    if (!$this->head()->parents) {
                        throw new VcsError('cannot amend the root commit');
                    }
                    $this->record($this->head()->parents, $this->index, $rest);
                    break;
                case 'STATUS':
                    $this->status();
                    break;
                case 'LS':
                case 'CAT':
                    $revision = $command === 'LS' ? ($args[0] ?? null) : ($args[1] ?? null);
                    $tree = $revision !== null ? $this->resolve($revision)->tree : $this->work;
                    if ($command === 'LS') {
                        if (!$tree) {
                            echo "(empty)\n";
                        }
                        foreach ($this->paths($tree) as $p) {
                            echo "$p {$tree[$p]}\n";
                        }
                    } else {
                        if (!isset($tree[$path])) {
                            if ($revision !== null) {
                                $this->missingPath($path, $revision);
                            }
                            throw new VcsError("no such file '$path'");
                        }
                        echo $tree[$path], "\n";
                    }
                    break;
                case 'DIFF':
                    if (!$args) {
                        $this->changes($this->index, array_intersect_key($this->work, $this->index));
                    } elseif ($path === 'STAGED') {
                        $this->changes($this->head()->tree, $this->index);
                    } else {
                        $a = $this->resolve($path);
                        $b = $this->resolve($args[1]);
                        $this->changes($a->tree, $b->tree);
                    }
                    break;
                case 'LOG':
                    $current = $this->head();
                    $count = 0;
                    do {
                        echo $this->summary($current), "\n";
                        $count++;
                        if (!$current->parents || ($path !== null && $count === (int)$path)) {
                            break;
                        }
                        $current = $current->parents[0];
                    } while (true);
                    break;
                case 'SHOW':
                    $commit = $this->resolve($path ?? 'HEAD');
                    echo 'commit ', $this->summary($commit), "\n";
                    echo 'parents: ', $commit->parents ? implode(' ', array_map(fn($p) => $p->id, $commit->parents)) : 'none', "\n";
                    $this->changes($commit->parents[0]->tree ?? [], $commit->tree);
                    break;
                case 'BLAME':
                    $commit = $this->head();
                    if (!isset($commit->tree[$path])) {
                        $this->missingPath($path, 'HEAD');
                    }
                    $value = $commit->tree[$path];
                    while ($commit->parents && ($commit->parents[0]->tree[$path] ?? null) === $value) {
                        $commit = $commit->parents[0];
                    }
                    echo "{$commit->id} ({$commit->message}) $value\n";
                    break;
                case 'BRANCH':
                case 'TAG':
                    $refs =& $this->tags;
                    if ($command === 'BRANCH') {
                        $refs =& $this->branches;
                    }
                    $kind = strtolower($command);
                    if ($path === '-d') {
                        $name = $args[1];
                        if (!isset($refs[$name])) {
                            throw new VcsError("no such $kind '$name'");
                        }
                        if ($command === 'BRANCH') {
                            if ($this->branch === $name) {
                                throw new VcsError("cannot delete current branch '$name'");
                            }
                            if (!$this->ancestor($refs[$name], $this->head())) {
                                throw new VcsError("branch '$name' is not fully merged");
                            }
                        }
                        $old = $refs[$name];
                        unset($refs[$name]);
                        echo "Deleted $kind $name (was {$old->id})\n";
                    } else {
                        if (isset($refs[$path])) {
                            throw new VcsError("$kind '$path' already exists");
                        }
                        $commit = $this->resolve($args[1] ?? 'HEAD');
                        $refs[$path] = $commit;
                        echo "Created $kind $path at {$commit->id}\n";
                    }
                    unset($refs);
                    break;
                case 'BRANCHES':
                    if ($this->branch === null) {
                        echo "* (HEAD detached at {$this->head()->id})\n";
                    }
                    foreach ($this->paths($this->branches) as $name) {
                        $commit = $this->branches[$name];
                        $mark = $name === $this->branch ? '*' : ' ';
                        echo "$mark $name {$commit->id} {$commit->message}\n";
                    }
                    break;
                case 'TAGS':
                    if (!$this->tags) {
                        echo "(no tags)\n";
                    }
                    foreach ($this->paths($this->tags) as $name) {
                        $commit = $this->tags[$name];
                        echo "$name {$commit->id} {$commit->message}\n";
                    }
                    break;
                case 'SWITCH':
                    if (!isset($this->branches[$path])) {
                        throw new VcsError("no such branch '$path'");
                    }
                    if ($this->branch === $path) {
                        echo "Already on '$path'\n";
                    } else {
                        $this->checkProgress();
                        $this->switchTree($this->branches[$path]->tree);
                        $this->branch = $path;
                        echo "Switched to branch '$path'\n";
                    }
                    break;
                case 'DETACH':
                    $commit = $this->resolve($path);
                    $this->checkProgress();
                    $this->switchTree($commit->tree);
                    $this->branch = null;
                    $this->detached = $commit;
                    $this->headReport();
                    break;
                case 'MERGE':
                    $target = $this->resolve($path);
                    $this->checkProgress();
                    $old = $this->head();
                    if ($this->ancestor($target, $old)) {
                        echo "Already up to date\n";
                    } elseif ($this->ancestor($old, $target)) {
                        $this->switchTree($target->tree);
                        $this->moveHead($target);
                        echo "Fast-forward {$old->id}..{$target->id}\n";
                    } else {
                        $this->checkUncommitted();
                        $base = $this->mergeBase($old, $target);
                        $this->apply($base->tree, $target->tree, 'merge', $target, "Merge $path", [$old, $target], $base);
                    }
                    break;
                case 'MERGEBASE':
                    $a = $this->resolve($path);
                    $b = $this->resolve($args[1]);
                    echo $this->mergeBase($a, $b)->id, "\n";
                    break;
                case 'REBASE':
                    $this->rebase($this->resolve($path));
                    break;
                case 'RESET':
                    $target = $this->resolve($args[1]);
                    if ($path === 'HARD') {
                        $selected = array_unique(array_merge($this->paths($this->index, $target->tree), $this->conflicts));
                        foreach ($selected as $p) {
                            $this->matchPath($this->work, $target->tree, $p);
                        }
                    }
                    if ($path !== 'SOFT') {
                        $this->index = $target->tree;
                    }
                    $this->moveHead($target);
                    $this->conflicts = [];
                    $this->operation = null;
                    $this->headReport();
                    break;
                case 'REVERT':
                case 'CHERRYPICK':
                    $target = $this->resolve($path);
                    $this->checkProgress();
                    $this->checkUncommitted();
                    $parentTree = $target->parents[0]->tree ?? [];
                    if ($command === 'REVERT') {
                        $this->apply($target->tree, $parentTree, 'revert', $target, 'Revert "' . $target->message . '"', [$this->head()]);
                    } else {
                        $this->apply($parentTree, $target->tree, 'cherry-pick', $target, $target->message, [$this->head()]);
                    }
                    break;
                case 'STASH':
                    $this->stashCommand($path);
                    break;
                case 'GRAPH':
                    $this->graph();
                    break;
                case 'DESCRIBE':
                    $commit = $this->resolve($path ?? 'HEAD');
                    $distance = $this->distances($commit);
                    $best = null;
                    $d = PHP_INT_MAX;
                    foreach ($this->paths($this->tags) as $name) {
                        $id = $this->tags[$name]->id;
                        if (isset($distance[$id]) && $distance[$id] < $d) {
                            $best = $name;
                            $d = $distance[$id];
                        }
                    }
                    if ($best === null) {
                        throw new VcsError("no tag can describe '{$commit->id}'");
                    }
                    echo $d === 0 ? $best : "$best-$d-g{$commit->id}", "\n";
                    break;
                case 'GC':
                    $roots = array_merge([$this->head()], array_values($this->branches), array_values($this->tags));
                    foreach ($this->stash as $entry) {
                        $roots[] = $entry[1];
                    }
                    if ($this->operation !== null) {
                        $roots[] = $this->operation[1];
                    }
                    $live = $this->reachable($roots);
                    $oldSize = count($this->commits);
                    $this->commits = array_intersect_key($this->commits, $live);
                    echo 'Removed unreachable commits: ', $oldSize - count($this->commits), "\n";
                    break;
            }
        } catch (VcsError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$vcs = new MiniVcs();
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === 'EXIT') {
        break;
    }
    $vcs->execute($line);
}
