<?php

class TrieNode
{
    public $children = [];
    public $terminal = false;
}

class Trie
{
    public $root;
    public $nodes = 1;
    public $words = 0;

    public function __construct()
    {
        $this->root = new TrieNode();
    }

    public function add($word)
    {
        $node = $this->root;
        foreach (str_split($word) as $letter) {
            if (!isset($node->children[$letter])) {
                $node->children[$letter] = new TrieNode();
                $this->nodes++;
            }
            $node = $node->children[$letter];
        }
        if ($node->terminal) {
            return false;
        }
        $node->terminal = true;
        $this->words++;
        return true;
    }

    public function find($prefix)
    {
        $node = $this->root;
        foreach (str_split($prefix) as $letter) {
            $node = $node->children[$letter] ?? null;
            if ($node === null) {
                return null;
            }
        }
        return $node;
    }

    public function has($word)
    {
        $node = $this->find($word);
        return $node !== null && $node->terminal;
    }

    public function anagrams($rack)
    {
        $counts = array_count_values(str_split($rack));
        $result = [];
        $visit = function ($node, $word) use (&$visit, &$counts, &$result) {
            if ($node->terminal) {
                $result[] = $word;
            }
            foreach ($node->children as $letter => $child) {
                $tile = ($counts[$letter] ?? 0) > 0 ? $letter : '?';
                if (($counts[$tile] ?? 0) === 0) {
                    continue;
                }
                $counts[$tile]--;
                $visit($child, $word . $letter);
                $counts[$tile]++;
            }
        };
        $visit($this->root, '');
        return $result;
    }
}
