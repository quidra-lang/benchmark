<?php
declare(strict_types=1);

abstract class Node
{
    public DirectoryNode $parent;
    public string $name = '';
    public function __construct(public readonly int $inode, public int $modified) {}
    abstract public function size(): int;
    abstract public function tag(): string;
    public function links(): int { return 1; }
}

final class DirectoryNode extends Node
{
    public array $entries = [];
    public function size(): int { return count($this->entries); }
    public function tag(): string { return 'd'; }
    public function links(): int
    {
        return 2 + count(array_filter($this->entries, fn(Node $node): bool => $node instanceof self));
    }
    public function children(bool $hidden = true): array
    {
        $children = array_values(array_filter($this->entries,
            fn(Node $node): bool => $hidden || $node->name[0] !== '.'));
        usort($children, fn(Node $a, Node $b): int => strcmp($a->name, $b->name));
        return $children;
    }
}

final class FileNode extends Node
{
    public function __construct(int $inode, int $modified, public array $lines = [])
    {
        parent::__construct($inode, $modified);
    }
    public function size(): int
    {
        $total = 0;
        foreach ($this->lines as $line) $total += strlen($line) + 1;
        return $total;
    }
    public function tag(): string { return '-'; }
}

final class LinkNode extends Node
{
    public function __construct(int $inode, int $modified, public readonly string $target)
    {
        parent::__construct($inode, $modified);
    }
    public function size(): int { return strlen($this->target); }
    public function tag(): string { return 'l'; }
}

enum Failure: string
{
    case None = '';
    case Missing = 'No such file or directory';
    case NotDirectory = 'Not a directory';
    case Loop = 'Too many levels of symbolic links';
}

final readonly class Resolution
{
    public function __construct(
        public ?Node $node = null,
        public Failure $error = Failure::None,
        public ?DirectoryNode $creationParent = null,
        public string $creationName = '',
    ) {}
    public function absent(): bool { return $this->creationParent !== null; }
}

function options(array $args): array
{
    $flags = [];
    $at = 0;
    while ($at < count($args) && str_starts_with($args[$at], '-')) {
        foreach (str_split(substr($args[$at], 1)) as $flag) $flags[$flag] = true;
        $at++;
    }
    return [$flags, array_slice($args, $at)];
}
function lastComponent(string $path): string
{
    $at = strrpos($path, '/');
    return $at === false ? $path : substr($path, $at + 1);
}
function joinPath(string $path, string $name): string { return $path === '/' ? "/$name" : "$path/$name"; }
function invalidSource(string $path): bool { return in_array(lastComponent($path), ['', '.', '..'], true); }

final class Shell
{
    private DirectoryNode $root;
    private DirectoryNode $current;
    private ?string $previous = null;
    private int $clock = 0;
    private int $nextInode = 2;

    public function __construct(private readonly Closure $terminal)
    {
        $this->root = new DirectoryNode(1, 0);
        $this->root->parent = $this->root;
        $this->current = $this->root;
    }
    private function error(string $text): void { ($this->terminal)($text); }
    private function absolute(Node $node): string
    {
        $parts = [];
        while ($node !== $this->root) {
            $parts[] = $node->name;
            $node = $node->parent;
        }
        return '/' . implode('/', array_reverse($parts));
    }
    private function descendant(Node $node, Node $ancestor): bool
    {
        while (true) {
            if ($node === $ancestor) return true;
            if ($node === $this->root) return false;
            $node = $node->parent;
        }
    }
    private function add(DirectoryNode $parent, string $name, Node $node): void
    {
        $parent->entries[':' . $name] = $node;
        $parent->modified = $this->clock;
        $node->parent = $parent;
        $node->name = $name;
    }
    private function makeDirectory(DirectoryNode $parent, string $name): DirectoryNode
    {
        $node = new DirectoryNode($this->nextInode++, $this->clock);
        $this->add($parent, $name, $node);
        return $node;
    }
    private function makeFile(DirectoryNode $parent, string $name, array $lines = []): FileNode
    {
        $node = new FileNode($this->nextInode++, $this->clock, $lines);
        $this->add($parent, $name, $node);
        return $node;
    }
    private function detach(Node $node): void
    {
        unset($node->parent->entries[':' . $node->name]);
        $node->parent->modified = $this->clock;
    }
    private function write(FileNode $file, array $lines, bool $append = false): void
    {
        if ($append) {
            foreach ($lines as $line) $file->lines[] = $line;
        } else {
            $file->lines = $lines;
        }
        $file->modified = $this->clock;
    }
    private function resolve(string $path, bool $follow = true, bool $parents = false): Resolution
    {
        $expansions = 0;
        $walk = function(string $path, DirectoryNode $base, bool $follow, bool $original)
            use (&$walk, &$expansions, $parents): Resolution {
            $node = str_starts_with($path, '/') ? $this->root : $base;
            $parts = array_values(array_filter(explode('/', $path), fn(string $part): bool => $part !== ''));
            foreach ($parts as $i => $part) {
                if (!$node instanceof DirectoryNode) return new Resolution(error: Failure::NotDirectory);
                if ($part === '.') continue;
                if ($part === '..') {
                    $node = $node->parent;
                    continue;
                }
                $last = $i + 1 === count($parts);
                $child = $node->entries[':' . $part] ?? null;
                if ($child === null) {
                    if ($original && $last) {
                        return new Resolution(error: Failure::Missing, creationParent: $node, creationName: $part);
                    }
                    if ($original && $parents) $child = $this->makeDirectory($node, $part);
                    else return new Resolution(error: Failure::Missing);
                }
                if ($child instanceof LinkNode && (!$last || $follow)) {
                    if (++$expansions > 8) return new Resolution(error: Failure::Loop);
                    $result = $walk($child->target, $node, true, false);
                    if ($result->node === null) return $result;
                    $child = $result->node;
                }
                $node = $child;
            }
            return new Resolution($node);
        };
        return $walk($path, $this->current, $follow, true);
    }
    private function cloneNode(Node $source, DirectoryNode $parent, string $name): void
    {
        if ($source instanceof DirectoryNode) {
            $directory = $this->makeDirectory($parent, $name);
            foreach ($source->children() as $child) $this->cloneNode($child, $directory, $child->name);
        } elseif ($source instanceof FileNode) {
            $this->makeFile($parent, $name, $source->lines);
        } else {
            $this->add($parent, $name, new LinkNode($this->nextInode++, $this->clock, $source->target));
        }
    }
    private function move(string $sourcePath, string $destination): void
    {
        $problem = fn(string $path, string $reason) => $this->error("mv: cannot move '$sourcePath' to '$path': $reason");
        if (invalidSource($sourcePath)) { $problem($destination, 'Invalid argument'); return; }
        $sourceResult = $this->resolve($sourcePath, false);
        $source = $sourceResult->node;
        if ($source === null) {
            $this->error("mv: cannot stat '$sourcePath': " . $sourceResult->error->value);
            return;
        }
        $destinationNode = $this->resolve($destination)->node;
        if ($destinationNode instanceof DirectoryNode) {
            $parent = $destinationNode;
            $name = lastComponent($sourcePath);
            $display = joinPath($destination, $name);
        } else {
            $result = $this->resolve($destination, false);
            if ($result->absent()) {
                $parent = $result->creationParent;
                $name = $result->creationName;
            } elseif ($result->node !== null) {
                $parent = $result->node->parent;
                $name = $result->node->name;
            } else { $problem($destination, $result->error->value); return; }
            $display = $destination;
        }
        $existing = $parent->entries[':' . $name] ?? null;
        if ($source instanceof DirectoryNode && $this->descendant($parent, $source)) {
            $this->error("mv: cannot move '$sourcePath' to a subdirectory of itself, '$display'");
        } elseif ($existing === $source) {
            $this->error("mv: '$sourcePath' and '$display' are the same file");
        } elseif ($existing !== null && $source instanceof DirectoryNode && !$existing instanceof DirectoryNode) {
            $this->error("mv: cannot overwrite non-directory '$display' with directory '$sourcePath'");
        } elseif (!$source instanceof DirectoryNode && $existing instanceof DirectoryNode) {
            $this->error("mv: cannot overwrite directory '$display' with non-directory '$sourcePath'");
        } elseif ($existing instanceof DirectoryNode && $existing->entries !== []) {
            $problem($display, 'Directory not empty');
        } elseif ($existing === $this->current) {
            $problem($display, 'Device or resource busy');
        } else {
            if ($existing !== null) $this->detach($existing);
            $this->detach($source);
            $this->add($parent, $name, $source);
        }
    }
    private function copyNode(string $sourcePath, string $destination, bool $recursive): void
    {
        $problem = fn(string $path, string $reason) => $this->error("cp: cannot copy '$sourcePath' to '$path': $reason");
        if (invalidSource($sourcePath)) { $problem($destination, 'Invalid argument'); return; }
        $sourceResult = $this->resolve($sourcePath);
        $source = $sourceResult->node;
        if ($source === null) {
            $this->error("cp: cannot stat '$sourcePath': " . $sourceResult->error->value);
            return;
        }
        if ($source instanceof DirectoryNode && !$recursive) {
            $this->error("cp: -r not specified; omitting directory '$sourcePath'");
            return;
        }
        $result = $this->resolve($destination);
        if ($result->node === null && !$result->absent()) {
            $problem($destination, $result->error->value);
            return;
        }
        $display = $result->node instanceof DirectoryNode ? joinPath($destination, lastComponent($sourcePath)) : $destination;
        $target = $this->resolve($display, !$source instanceof DirectoryNode);
        if ($source instanceof DirectoryNode) {
            if ($target->node !== null) $problem($display, 'File exists');
            elseif ($this->descendant($target->creationParent, $source)) {
                $this->error("cp: cannot copy a directory, '$sourcePath', into itself, '$display'");
            } else $this->cloneNode($source, $target->creationParent, $target->creationName);
        } elseif ($target->absent()) {
            $this->makeFile($target->creationParent, $target->creationName, $source->lines);
        } elseif ($target->node === $source) {
            $this->error("cp: '$sourcePath' and '$display' are the same file");
        } elseif ($target->node instanceof DirectoryNode) {
            $this->error("cp: cannot overwrite directory '$display' with non-directory '$sourcePath'");
        } elseif ($target->node instanceof FileNode) {
            $this->write($target->node, $source->lines);
        } else $problem($display, $target->error->value);
    }
    private function readInputs(string $command, array $paths, array $input, Closure $consume): void
    {
        if ($paths === []) { $consume($input, null); return; }
        foreach ($paths as $path) {
            $result = $this->resolve($path);
            if ($result->node === null) $this->error("$command: $path: " . $result->error->value);
            elseif ($result->node instanceof DirectoryNode) $this->error("$command: $path: Is a directory");
            else $consume($result->node->lines, $path);
        }
    }
    private function walk(Node $node, string $path, Closure $visit, ?int $maxDepth = null, int $depth = 0): void
    {
        $visit($node, $path, $depth);
        if ($node instanceof DirectoryNode && ($maxDepth === null || $depth < $maxDepth)) {
            foreach ($node->children() as $child) $this->walk($child, joinPath($path, $child->name), $visit, $maxDepth, $depth + 1);
        }
    }
    private function listNodes(array $args, Closure $output): void
    {
        [$flags, $paths] = options($args);
        if ($paths === []) $paths = ['.'];
        foreach ($paths as $path) {
            $result = $this->resolve($path, !isset($flags['l']));
            $node = $result->node;
            if ($node === null) {
                $this->error("ls: cannot access '$path': " . $result->error->value);
                continue;
            }
            $entries = [];
            if ($node instanceof DirectoryNode) {
                if (count($paths) >= 2) $output("$path:");
                if (isset($flags['a'])) $entries = [['.', $node], ['..', $node->parent]];
                foreach ($node->children(isset($flags['a'])) as $child) $entries[] = [$child->name, $child];
            } else $entries[] = [$path, $node];
            if (isset($flags['t'])) usort($entries, fn(array $a, array $b): int => $b[1]->modified <=> $a[1]->modified);
            if (isset($flags['r'])) $entries = array_reverse($entries);
            $widths = [0, 0, 0];
            foreach ($entries as [, $node]) {
                foreach ([$node->links(), $node->size(), $node->modified] as $i => $number) {
                    $widths[$i] = max($widths[$i], strlen((string)$number));
                }
            }
            foreach ($entries as [$name, $node]) {
                if (!isset($flags['l'])) { $output($name); continue; }
                $line = $node->tag();
                foreach ([$node->links(), $node->size(), $node->modified] as $i => $number) {
                    $line .= ' ' . str_pad((string)$number, $widths[$i], ' ', STR_PAD_LEFT);
                }
                $line .= ' ' . $name;
                if ($node instanceof LinkNode) $line .= ' -> ' . $node->target;
                $output($line);
            }
        }
    }
    private function find(array $args, Closure $output): void
    {
        $at = 0;
        $path = $args !== [] && !str_starts_with($args[0], '-') ? $args[$at++] : '.';
        $tests = [];
        while ($at < count($args)) {
            $tests[$args[$at]] = $args[$at + 1];
            $at += 2;
        }
        $result = $this->resolve($path);
        if ($result->node === null) {
            $this->error("find: '$path': " . $result->error->value);
            return;
        }
        $this->walk($result->node, $path, function(Node $node, string $display, int $depth) use ($path, $tests, $output): void {
            $name = $depth === 0 ? ($path === '/' ? '/' : lastComponent($path)) : $node->name;
            $kind = $node instanceof FileNode ? 'f' : $node->tag();
            if ((!isset($tests['-name']) || globMatch($tests['-name'], $name)) &&
                (!isset($tests['-type']) || $tests['-type'] === $kind)) $output($display);
        }, isset($tests['-maxdepth']) ? (int)$tests['-maxdepth'] : null);
    }
    private function diskUsage(array $args, Closure $output): void
    {
        [$flags, $paths] = options($args);
        if ($paths === []) $paths = ['.'];
        $report = function(Node $node, string $path, bool $show) use (&$report, $flags, $output): int {
            $total = $node instanceof DirectoryNode ? 0 : $node->size();
            if ($node instanceof DirectoryNode) {
                foreach ($node->children() as $child) {
                    $total += $report($child, joinPath($path, $child->name),
                        !isset($flags['s']) && ($child instanceof DirectoryNode || isset($flags['a'])));
                }
            }
            if ($show) $output("$total $path");
            return $total;
        };
        foreach ($paths as $path) {
            $result = $this->resolve($path);
            if ($result->node === null) $this->error("du: cannot access '$path': " . $result->error->value);
            else $report($result->node, $path, true);
        }
    }
    private function tree(array $args, Closure $output): void
    {
        [$flags, $paths] = options($args);
        $path = $paths[0] ?? '.';
        $result = $this->resolve($path);
        if ($result->node === null) { $this->error("tree: $path: " . $result->error->value); return; }
        if (!$result->node instanceof DirectoryNode) { $this->error("tree: $path: Not a directory"); return; }
        $directories = 0;
        $files = 0;
        $draw = function(DirectoryNode $directory, string $prefix) use (&$draw, &$directories, &$files, $flags, $output): void {
            $children = $directory->children(isset($flags['a']));
            foreach ($children as $i => $node) {
                $last = $i + 1 === count($children);
                $line = $prefix . ($last ? '`-- ' : '|-- ') . $node->name;
                if ($node instanceof LinkNode) $line .= ' -> ' . $node->target;
                $output($line);
                if ($node instanceof DirectoryNode) {
                    $directories++;
                    $draw($node, $prefix . ($last ? '    ' : '|   '));
                } else $files++;
            }
        };
        $output($path);
        $draw($result->node, '');
        $output("$directories " . ($directories === 1 ? 'directory' : 'directories') .
            ", $files " . ($files === 1 ? 'file' : 'files'));
    }
    private function wordCount(array $args, array $input, Closure $output): void
    {
        [$flags, $paths] = options($args);
        if ($flags === []) $flags = ['l' => true, 'w' => true, 'c' => true];
        $totals = [0, 0, 0];
        $report = function(array $counts, ?string $name) use ($flags, $output): void {
            $selected = [];
            foreach (['l', 'w', 'c'] as $i => $flag) if (isset($flags[$flag])) $selected[] = $counts[$i];
            $output(implode(' ', $selected) . ($name === null ? '' : ' ' . $name));
        };
        $this->readInputs('wc', $paths, $input, function(array $lines, ?string $name) use (&$totals, $report): void {
            $counts = [count($lines), 0, 0];
            foreach ($lines as $line) {
                $inside = false;
                $length = strlen($line);
                for ($i = 0; $i < $length; $i++) {
                    if ($line[$i] !== ' ' && !$inside) $counts[1]++;
                    $inside = $line[$i] !== ' ';
                }
                $counts[2] += $length + 1;
            }
            foreach ($counts as $i => $count) $totals[$i] += $count;
            $report($counts, $name);
        });
        if (count($paths) >= 2) $report($totals, 'total');
    }
    private function ends(string $command, array $args, array $input, Closure $output): void
    {
        $explicit = ($args[0] ?? '') === '-n';
        $count = $explicit ? $args[1] : '10';
        $special = $count[0] === '-' || $count[0] === '+';
        $amount = (int)($special ? substr($count, 1) : $count);
        $this->readInputs($command, array_slice($args, $explicit ? 2 : 0), $input,
            function(array $lines) use ($command, $amount, $special, $output): void {
                $first = 0;
                $end = count($lines);
                if ($command === 'head') $end = $special ? max(0, $end - $amount) : min($end, $amount);
                else $first = $special ? min($end, max(0, $amount - 1)) : max(0, $end - $amount);
                for ($i = $first; $i < $end; $i++) $output($lines[$i]);
            });
    }
    private function grep(array $args, array $input, Closure $output): void
    {
        [$flags, $rest] = options($args);
        $pattern = isset($flags['i']) ? strtolower($rest[0]) : $rest[0];
        $paths = array_slice($rest, 1);
        $consume = function(array $lines, ?string $name) use ($flags, $pattern, $paths, $output): void {
            $prefix = count($paths) >= 2 || isset($flags['r']) ? "$name:" : '';
            $selected = 0;
            foreach ($lines as $i => $line) {
                $compared = isset($flags['i']) ? strtolower($line) : $line;
                if (str_contains($compared, $pattern) === isset($flags['v'])) continue;
                $selected++;
                if (!isset($flags['c'])) $output($prefix . (isset($flags['n']) ? ($i + 1) . ':' : '') . $line);
            }
            if (isset($flags['c'])) $output($prefix . $selected);
        };
        if (!isset($flags['r'])) { $this->readInputs('grep', $paths, $input, $consume); return; }
        foreach ($paths === [] ? ['.'] : $paths as $path) {
            $result = $this->resolve($path);
            if ($result->node === null) $this->error("grep: $path: " . $result->error->value);
            else $this->walk($result->node, $path, function(Node $node, string $display) use ($consume): void {
                if ($node instanceof FileNode) $consume($node->lines, $display);
            });
        }
    }
    private function sortLines(array $args, array $input, Closure $output): void
    {
        [$flags, $paths] = options($args);
        $lines = [];
        $this->readInputs('sort', $paths, $input, function(array $part) use (&$lines): void {
            foreach ($part as $line) $lines[] = $line;
        });
        usort($lines, function(string $a, string $b) use ($flags): int {
            $comparison = isset($flags['n']) ? numericPrefix($a) <=> numericPrefix($b) : 0;
            return $comparison !== 0 ? $comparison : strcmp($a, $b);
        });
        if (isset($flags['r'])) $lines = array_reverse($lines);
        foreach ($lines as $line) $output($line);
    }
    private function unique(array $args, array $input, Closure $output): void
    {
        [$flags, $paths] = options($args);
        $this->readInputs('uniq', $paths, $input, function(array $lines) use ($flags, $output): void {
            for ($first = 0; $first < count($lines); $first = $end) {
                $end = $first + 1;
                while ($end < count($lines) && $lines[$end] === $lines[$first]) $end++;
                $output((isset($flags['c']) ? ($end - $first) . ' ' : '') . $lines[$first]);
            }
        });
    }
    private function execute(string $text, array $input, Closure $output): void
    {
        $words = explode(' ', $text);
        $command = $words[0];
        $args = array_slice($words, 1);
        switch ($command) {
            case 'pwd': $output($this->absolute($this->current)); break;
            case 'echo': $output(substr($text, 5)); break;
            case 'cd':
                $back = ($args[0] ?? '') === '-';
                if ($back && $this->previous === null) { $this->error('cd: OLDPWD not set'); break; }
                $path = $back ? $this->previous : ($args[0] ?? '/');
                $result = $this->resolve($path);
                if ($result->node === null) $this->error("cd: $path: " . $result->error->value);
                elseif (!$result->node instanceof DirectoryNode) $this->error("cd: $path: Not a directory");
                else {
                    $this->previous = $this->absolute($this->current);
                    $this->current = $result->node;
                    if ($back) $output($this->absolute($this->current));
                }
                break;
            case 'mkdir':
                [$flags, $paths] = options($args);
                foreach ($paths as $path) {
                    $result = $this->resolve($path, false, isset($flags['p']));
                    if ($result->absent()) $this->makeDirectory($result->creationParent, $result->creationName);
                    elseif ($result->node === null) $this->error("mkdir: cannot create directory '$path': " . $result->error->value);
                    elseif (!isset($flags['p']) || !$this->resolve($path)->node instanceof DirectoryNode) {
                        $this->error("mkdir: cannot create directory '$path': File exists");
                    }
                }
                break;
            case 'touch':
                foreach ($args as $path) {
                    $result = $this->resolve($path);
                    if ($result->absent()) $this->makeFile($result->creationParent, $result->creationName);
                    elseif ($result->node !== null) $result->node->modified = $this->clock;
                    else $this->error("touch: cannot touch '$path': " . $result->error->value);
                }
                break;
            case 'cat':
                $this->readInputs($command, $args, $input, function(array $lines) use ($output): void {
                    foreach ($lines as $line) $output($line);
                });
                break;
            case 'ls': $this->listNodes($args, $output); break;
            case 'stat':
                foreach ($args as $path) {
                    $result = $this->resolve($path, false);
                    $node = $result->node;
                    if ($node === null) { $this->error("stat: cannot stat '$path': " . $result->error->value); continue; }
                    $kind = match (true) {
                        $node instanceof DirectoryNode => 'directory',
                        $node instanceof LinkNode => 'symbolic link',
                        $node->lines === [] => 'regular empty file',
                        default => 'regular file',
                    };
                    $output("$path: $kind, size " . $node->size() . ", inode $node->inode, links " .
                        $node->links() . ", modified $node->modified");
                }
                break;
            case 'rm':
            case 'rmdir':
                [$flags, $paths] = $command === 'rm' ? options($args) : [[], $args];
                foreach ($paths as $path) {
                    $problem = fn(string $reason) => $this->error($command === 'rm'
                        ? "rm: cannot remove '$path': $reason" : "rmdir: failed to remove '$path': $reason");
                    if (in_array(lastComponent($path), ['.', '..'], true)) {
                        if ($command === 'rm') $this->error("rm: refusing to remove '.' or '..' directory: skipping '$path'");
                        else $problem('Invalid argument');
                        continue;
                    }
                    $result = $this->resolve($path, false);
                    $node = $result->node;
                    if ($node === null) {
                        if (!($command === 'rm' && isset($flags['f']) && $result->error === Failure::Missing)) {
                            $problem($result->error->value);
                        }
                    } elseif ($command === 'rm' && $node instanceof DirectoryNode && !isset($flags['r'])) {
                        $problem('Is a directory');
                    } elseif ($command === 'rmdir' && !$node instanceof DirectoryNode) {
                        $problem('Not a directory');
                    } elseif ($this->descendant($this->current, $node)) {
                        $problem('Device or resource busy');
                    } elseif ($command === 'rmdir' && $node->entries !== []) {
                        $problem('Directory not empty');
                    } else $this->detach($node);
                }
                break;
            case 'mv':
            case 'cp':
                [$flags, $paths] = $command === 'cp' ? options($args) : [[], $args];
                $destination = array_pop($paths);
                if (count($paths) >= 2 && !$this->resolve($destination)->node instanceof DirectoryNode) {
                    $this->error("$command: target '$destination' is not a directory");
                    break;
                }
                foreach ($paths as $source) {
                    if ($command === 'mv') $this->move($source, $destination);
                    else $this->copyNode($source, $destination, isset($flags['r']));
                }
                break;
            case 'ln':
                $target = $args[1];
                $path = $args[2];
                $result = $this->resolve($path, false);
                if ($result->absent()) {
                    $this->add($result->creationParent, $result->creationName, new LinkNode($this->nextInode++, $this->clock, $target));
                } else {
                    $reason = $result->node === null ? $result->error->value : 'File exists';
                    $this->error("ln: failed to create symbolic link '$path': $reason");
                }
                break;
            case 'readlink':
            case 'realpath':
                $path = $args[0];
                $result = $this->resolve($path, $command === 'realpath');
                if ($result->node === null) $this->error("$command: $path: " . $result->error->value);
                elseif ($command === 'realpath') $output($this->absolute($result->node));
                elseif ($result->node instanceof LinkNode) $output($result->node->target);
                else $this->error("readlink: $path: Invalid argument");
                break;
            case 'find': $this->find($args, $output); break;
            case 'du': $this->diskUsage($args, $output); break;
            case 'tree': $this->tree($args, $output); break;
            case 'wc': $this->wordCount($args, $input, $output); break;
            case 'head':
            case 'tail': $this->ends($command, $args, $input, $output); break;
            case 'grep': $this->grep($args, $input, $output); break;
            case 'sort': $this->sortLines($args, $input, $output); break;
            case 'uniq': $this->unique($args, $input, $output); break;
            default: $this->error("$command: command not found");
        }
    }
    public function process(string $line): void
    {
        $this->clock++;
        $this->error($this->absolute($this->current) . '$ ' . $line);
        $pipeline = $line;
        $redirect = null;
        $marker = strpos($line, ' >');
        if ($marker !== false) {
            $pipeline = substr($line, 0, $marker);
            $append = $line[$marker + 2] === '>';
            $path = substr($line, $marker + ($append ? 4 : 3));
            $result = $this->resolve($path);
            if ($result->absent()) $redirect = $this->makeFile($result->creationParent, $result->creationName);
            elseif ($result->node instanceof FileNode) {
                $redirect = $result->node;
                if (!$append) $this->write($redirect, []);
            } else {
                $reason = $result->node instanceof DirectoryNode ? 'Is a directory' : $result->error->value;
                $this->error("sh: $path: $reason");
                return;
            }
        }
        $input = [];
        $commands = explode(' | ', $pipeline);
        foreach ($commands as $i => $command) {
            $output = [];
            $emit = $i + 1 === count($commands) && $redirect === null ? $this->terminal :
                static function(string $text) use (&$output): void { $output[] = $text; };
            $this->execute($command, $input, $emit);
            $input = $output;
        }
        if ($redirect !== null && $input !== []) $this->write($redirect, $input, true);
    }
}

function globMatch(string $pattern, string $text): bool
{
    $previous = array_fill(0, strlen($text) + 1, false);
    $previous[0] = true;
    foreach (str_split($pattern) as $character) {
        $next = array_fill(0, strlen($text) + 1, false);
        $next[0] = $character === '*' && $previous[0];
        for ($i = 1; $i <= strlen($text); $i++) {
            $next[$i] = $character === '*' ? $previous[$i] || $next[$i - 1] :
                $previous[$i - 1] && ($character === '?' || $character === $text[$i - 1]);
        }
        $previous = $next;
    }
    return $previous[strlen($text)];
}
function numericPrefix(string $line): int
{
    $negative = str_starts_with($line, '-');
    $at = $negative ? 1 : 0;
    $value = 0;
    while ($at < strlen($line) && $line[$at] >= '0' && $line[$at] <= '9') {
        $value = $value * 10 + ord($line[$at]) - 48;
        $at++;
    }
    return $negative ? -$value : $value;
}

$shell = new Shell(static function(string $line): void { echo $line, "\n"; });
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === 'exit') break;
    $shell->process($line);
}
