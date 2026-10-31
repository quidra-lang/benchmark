<?php
declare(strict_types=1);

namespace MailThreads;

final class Container
{
    public ?Message $message = null;
    public ?self $parent = null;
    public array $children = [];
    public ?string $subject = null;
    public function __construct(public string $id) {}

    public function isAncestorOrSelf(self $other): bool
    {
        while (true) {
            if ($other === $this) {
                return true;
            }
            if ($other->parent === null) {
                return false;
            }
            $other = $other->parent;
        }
    }
}

function adopt(Container $parent, Container $child): void
{
    $child->parent = $parent;
    $parent->children[] = $child;
}

function pruneContainers(array $containers, bool $atRoot): array
{
    $result = [];
    foreach ($containers as $container) {
        $container->children = pruneContainers($container->children, false);
        if ($container->message !== null || $atRoot && count($container->children) >= 2) {
            $result[] = $container;
        } else {
            foreach ($container->children as $child) {
                $child->parent = $atRoot ? null : $container->parent;
                $result[] = $child;
            }
        }
    }
    return $result;
}

function compareKeys(array $a, array $b): int
{
    return ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]) ?: strcmp($a[2], $b[2]) ?: ($a[3] <=> $b[3]);
}

function containerKey(Container $container): array
{
    if ($container->message !== null) {
        return $container->message->sortKey;
    }
    $best = null;
    foreach ($container->children as $child) {
        $key = containerKey($child);
        if ($best === null || compareKeys($key, $best) < 0) {
            $best = $key;
        }
    }
    return $best;
}

function sortContainers(array &$containers): void
{
    foreach ($containers as $container) {
        sortContainers($container->children);
    }
    usort($containers, static fn(Container $a, Container $b): int => compareKeys(containerKey($a), containerKey($b)));
}

function rootSubject(Container $root): string
{
    return $root->message !== null ? $root->message->baseSubject : $root->children[0]->message->baseSubject;
}

function buildThreads(array $messages): array
{
    $table = $containers = [];
    $containerOf = static function (string $id) use (&$table, &$containers): Container {
        $key = '#' . $id;
        if (!isset($table[$key])) {
            $table[$key] = new Container($id);
            $containers[] = $table[$key];
        }
        return $table[$key];
    };
    foreach ($messages as $message) {
        if ($message->id !== '') {
            $container = $containerOf($message->id);
        } else {
            $container = new Container('');
            $containers[] = $container;
        }
        $container->message = $message;
        $references = array_map($containerOf, $message->references);
        for ($index = 0; $index + 1 < count($references); $index++) {
            $current = $references[$index];
            $following = $references[$index + 1];
            if ($following->parent === null && !$following->isAncestorOrSelf($current)) {
                adopt($current, $following);
            }
        }
        if ($container->parent !== null) {
            foreach ($container->parent->children as $index => $child) {
                if ($child === $container) {
                    array_splice($container->parent->children, $index, 1);
                    break;
                }
            }
            $container->parent = null;
        }
        if ($references !== [] && !$container->isAncestorOrSelf($references[count($references) - 1])) {
            adopt($references[count($references) - 1], $container);
        }
    }
    $roots = array_values(array_filter($containers, static fn(Container $container): bool => $container->parent === null));
    $roots = pruneContainers($roots, true);
    sortContainers($roots);
    $groups = [];
    foreach ($roots as $root) {
        $subject = rootSubject($root);
        if ($subject !== '') {
            $groups['#' . $subject][] = $root;
        }
    }
    $merged = [];
    foreach ($roots as $root) {
        $subject = rootSubject($root);
        if ($subject === '' || count($groups['#' . $subject]) === 1) {
            $merged[] = $root;
        }
    }
    foreach ($groups as $key => $group) {
        if (count($group) < 2) {
            continue;
        }
        $target = $original = null;
        $originals = 0;
        foreach ($group as $root) {
            if ($root->message === null && $target === null) {
                $target = $root;
            }
            if ($root->message !== null && !$root->message->reply) {
                $original = $root;
                $originals++;
            }
        }
        if ($target === null) {
            if ($originals === 1) {
                $target = $original;
            } else {
                $target = new Container('');
                $target->subject = substr($key, 1);
            }
        }
        foreach ($group as $root) {
            if ($root === $target) {
                continue;
            }
            if ($root->message !== null) {
                adopt($target, $root);
            } else {
                foreach ($root->children as $child) {
                    adopt($target, $child);
                }
            }
        }
        $merged[] = $target;
    }
    sortContainers($merged);
    return $merged;
}
