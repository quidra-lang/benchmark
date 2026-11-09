<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}

final readonly class Entry
{
    public function __construct(public int $key, public string $value) {}
    public function __toString(): string { return $this->key . '=' . $this->value; }
}

final class Node
{
    public function __construct(public array $entries = [], public array $children = []) {}
    public function leaf(): bool { return $this->children === []; }
    public function position(int $key): int
    {
        foreach ($this->entries as $i => $entry) {
            if ($key <= $entry->key) return $i;
        }
        return count($this->entries);
    }
    public function copy(): self { return new self($this->entries, $this->children); }
    public function sameContent(self $other): bool
    {
        if ($this->children !== $other->children || count($this->entries) !== count($other->entries)) return false;
        foreach ($this->entries as $i => $entry) {
            $old = $other->entries[$i];
            if ($entry->key !== $old->key || $entry->value !== $old->value) return false;
        }
        return true;
    }
    public function __toString(): string
    {
        return '[' . implode(' ', array_map(fn(Entry $entry): int => $entry->key, $this->entries)) . ']';
    }
}

final class Trace
{
    public array $lines = [], $cases = [];
    public function __construct(public readonly bool $enabled) {}
    public function emit(string $text): void { if ($this->enabled) $this->lines[] = $text; }
    public function record(string $name): void { $this->cases[] = $name; }
}

final readonly class Search
{
    public function __construct(public ?int $page, public int $position, public array $path) {}
}

final class Tree
{
    public array $pages = [];
    public int $root = 0, $splits = 0, $merges = 0, $borrows = 0;
    public function __construct(public readonly int $degree, bool $empty = true)
    {
        if ($empty) $this->pages[0] = new Node();
    }
    public function copy(): self
    {
        $result = new self($this->degree, false);
        foreach ($this->pages as $page => $node) $result->pages[$page] = $node->copy();
        $result->root = $this->root;
        $result->splits = $this->splits;
        $result->merges = $this->merges;
        $result->borrows = $this->borrows;
        return $result;
    }
    public function newPage(Node $node): int
    {
        $page = 0;
        while (isset($this->pages[$page])) $page++;
        $this->pages[$page] = $node;
        return $page;
    }
    public static function load(int $degree, array $tokens): self
    {
        $tree = new self($degree, false);
        $position = 0;
        $bad = static function() use (&$position): never {
            throw new CommandError('SYNTAX ' . ($position + 1));
        };
        $readEntry = static function() use ($tokens, &$position, $bad): Entry {
            $token = $tokens[$position] ?? null;
            if ($token === null || $token === '(' || $token === ')') $bad();
            [$key, $value] = explode('=', $token);
            $position++;
            return new Entry((int)$key, $value);
        };
        $readNode = function() use (&$readNode, $readEntry, $bad, $tokens, &$position, $tree): int {
            if (($tokens[$position] ?? null) !== '(') $bad();
            $position++;
            $node = new Node();
            $page = $tree->newPage($node);
            if (($tokens[$position] ?? null) === '(') {
                $node->children[] = $readNode();
                while (($tokens[$position] ?? null) !== ')') {
                    $node->entries[] = $readEntry();
                    $node->children[] = $readNode();
                }
            } else {
                while (($tokens[$position] ?? null) !== ')') $node->entries[] = $readEntry();
            }
            $position++;
            return $page;
        };
        $tree->root = $readNode();
        if ($position !== count($tokens)) $bad();
        return $tree;
    }
    public function entries(): array
    {
        $result = [];
        $visit = function(int $page) use (&$visit, &$result): void {
            $node = $this->pages[$page];
            if (!$node->leaf()) $visit($node->children[0]);
            foreach ($node->entries as $i => $entry) {
                $result[] = $entry;
                if (!$node->leaf()) $visit($node->children[$i + 1]);
            }
        };
        $visit($this->root);
        return $result;
    }
    public function height(): int
    {
        $page = $this->root;
        $depth = 0;
        while (!$this->pages[$page]->leaf()) {
            $page = $this->pages[$page]->children[0];
            $depth++;
        }
        return $depth;
    }
    public function search(int $key): Search
    {
        $page = $this->root;
        $path = [];
        while (true) {
            $node = $this->pages[$page];
            $path[] = (string)$node;
            $position = $node->position($key);
            if ($position < count($node->entries) && $node->entries[$position]->key === $key) {
                return new Search($page, $position, $path);
            }
            if ($node->leaf()) return new Search(null, $position, $path);
            $page = $node->children[$position];
        }
    }
    public function violation(): ?string
    {
        $reference = null;
        $visit = function(int $page, string $location, int $depth, ?int $low, ?int $high) use (&$visit, &$reference): ?string {
            $node = $this->pages[$page];
            $count = count($node->entries);
            $minimum = $page === $this->root ? ($node->leaf() ? 0 : 1) : $this->degree - 1;
            $maximum = 2 * $this->degree - 1;
            if ($count < $minimum || $count > $maximum) {
                return "COUNT at=$location node=$node keys=$count allowed=$minimum..$maximum";
            }
            for ($i = 0; $i + 1 < $count; $i++) {
                $left = $node->entries[$i]->key;
                $right = $node->entries[$i + 1]->key;
                if ($left >= $right) return "ORDER at=$location node=$node $left>=$right";
            }
            foreach ($node->entries as $entry) {
                if (($low !== null && $entry->key <= $low) || ($high !== null && $entry->key >= $high)) {
                    $lo = $low ?? '-inf';
                    $hi = $high ?? '+inf';
                    return "RANGE at=$location node=$node key=$entry->key low=$lo high=$hi";
                }
            }
            if ($node->leaf()) {
                if ($reference === null) $reference = $depth;
                elseif ($depth !== $reference) return "DEPTH at=$location node=$node depth=$depth expected=$reference";
            }
            foreach ($node->children as $i => $child) {
                $problem = $visit($child, "$location.$i", $depth + 1,
                    $i === 0 ? $low : $node->entries[$i - 1]->key,
                    $i === $count ? $high : $node->entries[$i]->key);
                if ($problem !== null) return $problem;
            }
            return null;
        };
        return $visit($this->root, 'root', 0, null, null);
    }
    public function changes(self $before): array
    {
        $writes = $frees = 0;
        foreach ($this->pages as $page => $node) {
            if (!isset($before->pages[$page]) || !$node->sameContent($before->pages[$page])) $writes++;
        }
        foreach ($before->pages as $page => $_) if (!isset($this->pages[$page])) $frees++;
        return ['writes' => $writes, 'frees' => $frees];
    }
    private function splitChild(int $parentPage, int $position, Trace $trace): void
    {
        $parent = $this->pages[$parentPage];
        $childPage = $parent->children[$position];
        $child = $this->pages[$childPage];
        $middle = $child->entries[$this->degree - 1];
        $right = new Node(array_slice($child->entries, $this->degree),
            $child->leaf() ? [] : array_slice($child->children, $this->degree));
        $rightPage = $this->newPage($right);
        $trace->emit("STEP split page=$childPage keys=$child up=$middle->key new=$rightPage");
        $child->entries = array_slice($child->entries, 0, $this->degree - 1);
        if (!$child->leaf()) $child->children = array_slice($child->children, 0, $this->degree);
        array_splice($parent->entries, $position, 0, [$middle]);
        array_splice($parent->children, $position + 1, 0, [$rightPage]);
        $this->splits++;
    }
    public function upsert(int $key, string $value, Trace $trace): ?string
    {
        $found = $this->search($key);
        if ($found->page !== null) {
            $node = $this->pages[$found->page];
            $old = $node->entries[$found->position]->value;
            $node->entries[$found->position] = new Entry($key, $value);
            return $old;
        }
        if (count($this->pages[$this->root]->entries) === 2 * $this->degree - 1) {
            $previous = $this->root;
            $this->root = $this->newPage(new Node([], [$previous]));
            $trace->emit("STEP grow page=$this->root");
            $this->splitChild($this->root, 0, $trace);
        }
        $page = $this->root;
        while (!$this->pages[$page]->leaf()) {
            $node = $this->pages[$page];
            $position = $node->position($key);
            if (count($this->pages[$node->children[$position]]->entries) === 2 * $this->degree - 1) {
                $this->splitChild($page, $position, $trace);
                if ($key > $node->entries[$position]->key) $position++;
            }
            $page = $node->children[$position];
        }
        $node = $this->pages[$page];
        array_splice($node->entries, $node->position($key), 0, [new Entry($key, $value)]);
        $trace->emit("STEP place page=$page keys=$node");
        return null;
    }
    private function merge(int $parentPage, int $position, string $case, Trace $trace): int
    {
        $parent = $this->pages[$parentPage];
        $leftPage = $parent->children[$position];
        $rightPage = $parent->children[$position + 1];
        $left = $this->pages[$leftPage];
        $right = $this->pages[$rightPage];
        $left->entries = array_merge($left->entries, [$parent->entries[$position]], $right->entries);
        $left->children = array_merge($left->children, $right->children);
        array_splice($parent->entries, $position, 1);
        array_splice($parent->children, $position + 1, 1);
        unset($this->pages[$rightPage]);
        $this->merges++;
        $trace->emit("STEP $case page=$parentPage merge=$leftPage+$rightPage keys=$left");
        if ($parentPage === $this->root && $parent->entries === []) {
            $this->root = $leftPage;
            unset($this->pages[$parentPage]);
            $trace->emit("STEP shrink page=$leftPage");
        }
        return $leftPage;
    }
    private function removeAt(int $page, int $key, Trace $trace): void
    {
        $node = $this->pages[$page];
        $position = $node->position($key);
        if ($position < count($node->entries) && $node->entries[$position]->key === $key) {
            if ($node->leaf()) {
                $trace->record('1');
                array_splice($node->entries, $position, 1);
                $trace->emit("STEP 1 page=$page keys=$node");
                return;
            }
            $left = $node->children[$position];
            $right = $node->children[$position + 1];
            if (count($this->pages[$left]->entries) >= $this->degree) {
                $last = $left;
                while (!$this->pages[$last]->leaf()) $last = $this->pages[$last]->children[array_key_last($this->pages[$last]->children)];
                $predecessor = $this->pages[$last]->entries[array_key_last($this->pages[$last]->entries)];
                $trace->record('2a');
                $trace->emit("STEP 2a page=$page pred=$predecessor->key");
                $this->removeAt($left, $predecessor->key, $trace);
                $node->entries[$position] = $predecessor;
            } elseif (count($this->pages[$right]->entries) >= $this->degree) {
                $first = $right;
                while (!$this->pages[$first]->leaf()) $first = $this->pages[$first]->children[0];
                $successor = $this->pages[$first]->entries[0];
                $trace->record('2b');
                $trace->emit("STEP 2b page=$page succ=$successor->key");
                $this->removeAt($right, $successor->key, $trace);
                $node->entries[$position] = $successor;
            } else {
                $trace->record('2c');
                $child = $this->merge($page, $position, '2c', $trace);
                $this->removeAt($child, $key, $trace);
            }
            return;
        }
        $childPage = $node->children[$position];
        $child = $this->pages[$childPage];
        if (count($child->entries) === $this->degree - 1) {
            $left = $position > 0 ? $node->children[$position - 1] : null;
            $right = $position < count($node->entries) ? $node->children[$position + 1] : null;
            if ($left !== null && count($this->pages[$left]->entries) >= $this->degree) {
                $sibling = $this->pages[$left];
                $trace->record('3a-left');
                array_unshift($child->entries, $node->entries[$position - 1]);
                $node->entries[$position - 1] = array_pop($sibling->entries);
                if (!$sibling->leaf()) array_unshift($child->children, array_pop($sibling->children));
                $this->borrows++;
                $trace->emit("STEP 3a-left page=$page child=$childPage from=$left keys=$child");
            } elseif ($right !== null && count($this->pages[$right]->entries) >= $this->degree) {
                $sibling = $this->pages[$right];
                $trace->record('3a-right');
                $child->entries[] = $node->entries[$position];
                $node->entries[$position] = array_shift($sibling->entries);
                if (!$sibling->leaf()) $child->children[] = array_shift($sibling->children);
                $this->borrows++;
                $trace->emit("STEP 3a-right page=$page child=$childPage from=$right keys=$child");
            } elseif ($left !== null) {
                $trace->record('3b-left');
                $childPage = $this->merge($page, $position - 1, '3b-left', $trace);
            } else {
                $trace->record('3b-right');
                $childPage = $this->merge($page, $position, '3b-right', $trace);
            }
        }
        $this->removeAt($childPage, $key, $trace);
    }
    public function remove(int $key, Trace $trace): array
    {
        $trace->cases = [];
        $this->removeAt($this->root, $key, $trace);
        return $trace->cases;
    }
    public function scan(int $low, int $high): array
    {
        $result = [];
        $visited = 0;
        $visit = function(int $page) use (&$visit, &$result, &$visited, $low, $high): void {
            $visited++;
            $node = $this->pages[$page];
            $count = count($node->entries);
            for ($i = 0; $i <= $count; $i++) {
                if (!$node->leaf() && ($i === 0 || $node->entries[$i - 1]->key < $high)
                    && ($i === $count || $node->entries[$i]->key > $low)) $visit($node->children[$i]);
                if ($i < $count && $low <= $node->entries[$i]->key && $node->entries[$i]->key <= $high) {
                    $result[] = $node->entries[$i];
                }
            }
        };
        $visit($this->root);
        return ['entries' => $result, 'visited' => $visited];
    }
    public function dump(): string
    {
        $tokens = [];
        $visit = function(int $page) use (&$visit, &$tokens): void {
            $node = $this->pages[$page];
            $tokens[] = '(';
            if (!$node->leaf()) $visit($node->children[0]);
            foreach ($node->entries as $i => $entry) {
                $tokens[] = (string)$entry;
                if (!$node->leaf()) $visit($node->children[$i + 1]);
            }
            $tokens[] = ')';
        };
        $visit($this->root);
        return implode(' ', $tokens);
    }
    public function compact(): void
    {
        $source = $this->entries();
        $children = $built = [];
        while (true) {
            $groups = intdiv(count($source) + 2 * $this->degree, 2 * $this->degree);
            $keys = count($source) - ($groups - 1);
            $size = intdiv($keys, $groups);
            $extra = $keys % $groups;
            $entryIndex = $childIndex = 0;
            $nodes = $separators = [];
            for ($group = 0; $group < $groups; $group++) {
                $count = $size + ($group < $extra ? 1 : 0);
                $nodes[] = count($built);
                $built[] = new Node(array_slice($source, $entryIndex, $count),
                    $children === [] ? [] : array_slice($children, $childIndex, $count + 1));
                $entryIndex += $count;
                $childIndex += $count + 1;
                if ($group + 1 < $groups) $separators[] = $source[$entryIndex++];
            }
            if ($groups === 1) {
                $oldRoot = $nodes[0];
                break;
            }
            $source = $separators;
            $children = $nodes;
        }
        $replacement = [];
        $nextPage = 0;
        $renumber = function(int $oldPage) use (&$renumber, $built, &$replacement, &$nextPage): int {
            $page = $nextPage++;
            $old = $built[$oldPage];
            $children = [];
            foreach ($old->children as $child) $children[] = $renumber($child);
            $replacement[$page] = new Node($old->entries, $children);
            return $page;
        };
        $this->root = $renumber($oldRoot);
        $this->pages = $replacement;
        $this->splits = $this->merges = $this->borrows = 0;
    }
}

enum CursorKind { case Fresh; case Key; case Begin; case End; }
final readonly class Cursor
{
    public function __construct(public CursorKind $kind, public int $key = 0) {}
}

final class Workbench
{
    private ?Tree $index = null, $saved = null;
    private Cursor $cursor;
    private bool $trace = false;
    public function __construct() { $this->cursor = new Cursor(CursorKind::Fresh); }
    private const NEEDS_VALID = ['INSERT', 'BULKLOAD', 'DELETE', 'DELRANGE', 'RANGE', 'COUNT',
        'MIN', 'MAX', 'FLOOR', 'CEIL', 'RANK', 'SELECT', 'SEEK', 'NEXT', 'PREV', 'HEIGHT', 'COMPACT'];

    private static function find(array $entries, Closure $predicate, bool $last = false): ?Entry
    {
        $result = null;
        foreach ($entries as $entry) {
            if (!$predicate($entry)) continue;
            $result = $entry;
            if (!$last) break;
        }
        return $result;
    }
    private static function summary(string $prefix, Tree $tree): string
    {
        $nodes = count($tree->pages);
        $keys = count($tree->entries());
        $status = $tree->violation() === null ? 'OK' : 'DAMAGED';
        return "$prefix nodes=$nodes keys=$keys $status";
    }
    public function process(string $line): array
    {
        $words = explode(' ', $line);
        $command = $words[0];
        if ($command === 'TRACE') {
            $this->trace = $words[1] === 'ON';
            return ['TRACE ' . $words[1]];
        }
        $first = isset($words[1]) ? (int)$words[1] : 0;
        $ranged = in_array($command, ['DELRANGE', 'RANGE', 'COUNT'], true);
        $second = $ranged ? (int)$words[2] : 0;
        if ($command === 'CREATE' || $command === 'LOAD') {
            if ($first < 2 || $first > 5) throw new CommandError("BAD DEGREE $first");
            $replacement = $command === 'CREATE' ? new Tree($first) : Tree::load($first, array_slice($words, 2));
            $this->index = $replacement;
            $this->cursor = new Cursor(CursorKind::Fresh);
            return [$command === 'CREATE' ? "CREATE t=$first" : self::summary("LOAD t=$first", $replacement)];
        }
        $tree = $this->index;
        if ($tree === null) throw new CommandError('NO INDEX');
        if (in_array($command, self::NEEDS_VALID, true) && $tree->violation() !== null) throw new CommandError('DAMAGED');
        $entries = $tree->entries();
        if ($ranged && $first > $second) throw new CommandError("BAD RANGE $first $second");
        if ($command === 'SELECT' && ($first < 1 || $first > count($entries))) throw new CommandError("BAD POSITION $first");
        if (($command === 'NEXT' || $command === 'PREV') && $this->cursor->kind === CursorKind::Fresh) throw new CommandError('NO CURSOR');
        if ($command === 'RESTORE' && $this->saved === null) throw new CommandError('NO SAVE');
        $output = [];
        $steps = new Trace($this->trace && ($command === 'INSERT' || $command === 'DELETE'));
        switch ($command) {
            case 'INSERT':
                $before = $tree->copy();
                $splits = $tree->splits;
                $old = $tree->upsert($first, $words[2], $steps);
                $writes = $tree->changes($before)['writes'];
                $output = $steps->lines;
                $output[] = $old === null
                    ? "INSERT $first NEW splits=" . ($tree->splits - $splits) . " height={$tree->height()} writes=$writes"
                    : "INSERT $first UPDATED old=$old writes=$writes";
                break;
            case 'BULKLOAD':
                $before = $tree->copy();
                $splits = $tree->splits;
                $inserted = $updated = 0;
                for ($i = 1; $i < count($words); $i += 2) {
                    if ($tree->upsert((int)$words[$i], $words[$i + 1], $steps) === null) $inserted++;
                    else $updated++;
                }
                $pairs = intdiv(count($words) - 1, 2);
                $writes = $tree->changes($before)['writes'];
                $output[] = "BULKLOAD pairs=$pairs new=$inserted updated=$updated splits=" . ($tree->splits - $splits)
                    . " height={$tree->height()} writes=$writes";
                break;
            case 'DELETE':
                $found = $tree->search($first);
                if ($found->page === null) {
                    $output[] = "DELETE $first NOT FOUND";
                } else {
                    $value = $tree->pages[$found->page]->entries[$found->position]->value;
                    $before = $tree->copy();
                    $cases = implode(',', $tree->remove($first, $steps));
                    $changes = $tree->changes($before);
                    $output = $steps->lines;
                    $output[] = "DELETE $first REMOVED value=$value cases=$cases height={$tree->height()} writes={$changes['writes']} frees={$changes['frees']}";
                }
                break;
            case 'DELRANGE':
                $before = $tree->copy();
                $merges = $tree->merges;
                $borrows = $tree->borrows;
                $removed = 0;
                foreach ($entries as $entry) {
                    if ($first <= $entry->key && $entry->key <= $second) {
                        $tree->remove($entry->key, $steps);
                        $removed++;
                    }
                }
                $changes = $tree->changes($before);
                $output[] = "DELRANGE $first $second removed=$removed merges=" . ($tree->merges - $merges)
                    . ' borrows=' . ($tree->borrows - $borrows)
                    . " height={$tree->height()} writes={$changes['writes']} frees={$changes['frees']}";
                break;
            case 'GET':
                $found = $tree->search($first);
                $result = $found->page === null ? 'NOT FOUND' : 'FOUND value=' . $tree->pages[$found->page]->entries[$found->position]->value;
                $output[] = "GET $first $result path=" . implode(' -> ', $found->path);
                break;
            case 'RANGE':
            case 'COUNT':
                $result = $tree->scan($first, $second);
                $output[] = "$command $first $second count=" . count($result['entries']) . " visited={$result['visited']}"
                    . ($command === 'RANGE' ? implode('', array_map(fn(Entry $entry): string => " $entry", $result['entries'])) : '');
                break;
            case 'MIN':
            case 'MAX':
                $output[] = "$command " . ($entries === [] ? 'EMPTY' : (string)$entries[$command === 'MIN' ? 0 : count($entries) - 1]);
                break;
            case 'FLOOR':
            case 'CEIL':
                $entry = $command === 'FLOOR'
                    ? self::find($entries, fn(Entry $value): bool => $value->key <= $first, true)
                    : self::find($entries, fn(Entry $value): bool => $value->key >= $first);
                $output[] = "$command $first " . ($entry === null ? 'NONE' : (string)$entry);
                break;
            case 'RANK':
                $rank = count(array_filter($entries, fn(Entry $entry): bool => $entry->key < $first));
                $output[] = "RANK $first $rank";
                break;
            case 'SELECT':
                $output[] = "SELECT $first " . $entries[$first - 1];
                break;
            case 'SEEK':
                $entry = self::find($entries, fn(Entry $value): bool => $value->key >= $first);
                $this->cursor = $entry === null ? new Cursor(CursorKind::End) : new Cursor(CursorKind::Key, $entry->key);
                $output[] = "SEEK $first " . ($entry === null ? 'END' : (string)$entry);
                break;
            case 'NEXT':
            case 'PREV':
                $entry = null;
                if ($command === 'NEXT') {
                    if ($this->cursor->kind === CursorKind::Begin) $entry = self::find($entries, fn(Entry $_): bool => true);
                    elseif ($this->cursor->kind === CursorKind::Key) {
                        $entry = self::find($entries, fn(Entry $value): bool => $value->key > $this->cursor->key);
                    }
                } else {
                    if ($this->cursor->kind === CursorKind::End) $entry = self::find($entries, fn(Entry $_): bool => true, true);
                    elseif ($this->cursor->kind === CursorKind::Key) {
                        $entry = self::find($entries, fn(Entry $value): bool => $value->key < $this->cursor->key, true);
                    }
                }
                $marker = $command === 'NEXT' ? 'END' : 'BEGIN';
                $kind = $command === 'NEXT' ? CursorKind::End : CursorKind::Begin;
                $this->cursor = $entry === null ? new Cursor($kind) : new Cursor(CursorKind::Key, $entry->key);
                $output[] = "$command " . ($entry === null ? $marker : (string)$entry);
                break;
            case 'PRINT':
                $level = [$tree->root];
                $depth = 0;
                while ($level !== []) {
                    $notations = $next = [];
                    foreach ($level as $page) {
                        $node = $tree->pages[$page];
                        $notations[] = (string)$node;
                        array_push($next, ...$node->children);
                    }
                    $output[] = "LEVEL $depth " . implode(' ', $notations);
                    $level = $next;
                    $depth++;
                }
                break;
            case 'PAGES':
                $pages = array_keys($tree->pages);
                sort($pages, SORT_NUMERIC);
                foreach ($pages as $page) {
                    $node = $tree->pages[$page];
                    $output[] = "PAGE $page $node kids=" . ($node->leaf() ? '-' : implode(',', $node->children));
                }
                break;
            case 'DUMP':
                $output[] = "DUMP $tree->degree " . $tree->dump();
                break;
            case 'HEIGHT':
                $output[] = "HEIGHT {$tree->height()}";
                break;
            case 'STATS':
                $nodes = count($tree->pages);
                $leaves = count(array_filter($tree->pages, fn(Node $node): bool => $node->leaf()));
                $keys = count($entries);
                $fill = intdiv(100 * $keys, (2 * $tree->degree - 1) * $nodes);
                $output[] = "STATS t=$tree->degree nodes=$nodes leaves=$leaves keys=$keys fill=$fill% splits=$tree->splits merges=$tree->merges borrows=$tree->borrows";
                break;
            case 'VERIFY':
                $problem = $tree->violation();
                $output[] = $problem === null ? 'VERIFY OK' : "VERIFY FAIL $problem";
                break;
            case 'REBUILD':
                $tree = new Tree($tree->degree);
                foreach ($entries as $entry) $tree->upsert($entry->key, $entry->value, $steps);
                $output[] = 'REBUILD entries=' . count($entries) . ' keys=' . count($tree->entries()) . ' nodes=' . count($tree->pages)
                    . " splits=$tree->splits height={$tree->height()}";
                break;
            case 'COMPACT':
                $nodes = count($tree->pages);
                $tree->compact();
                $output[] = "COMPACT nodes={$nodes}->" . count($tree->pages) . " height={$tree->height()}";
                break;
            case 'SAVE':
                $this->saved = $tree->copy();
                $output[] = self::summary('SAVE', $tree);
                break;
            case 'RESTORE':
                $tree = $this->saved->copy();
                $output[] = self::summary('RESTORE', $tree);
                break;
        }
        $this->index = $tree;
        return $output;
    }
}

$count = (int)trim(fgets(STDIN));
$workbench = new Workbench();
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        $output = $workbench->process($line);
        echo implode("\n", $output), "\n";
    } catch (CommandError $error) {
        echo 'ERROR ', $error->getMessage(), "\n";
    }
}
