<?php
declare(strict_types=1);

final class QueryParser
{
    private array $tokens;
    private int $position = 0;

    public function __construct(string $text)
    {
        preg_match_all("/[A-Z]+|[a-z][a-z0-9_]*|-?[0-9]+|'[a-z0-9_-]*'|<>|<=|>=|[=<>(),*]/", $text, $matches);
        $this->tokens = $matches[0];
    }

    private function take(): string
    {
        return $this->tokens[$this->position++];
    }

    private function accept(string $token): bool
    {
        if (($this->tokens[$this->position] ?? null) !== $token) {
            return false;
        }
        ++$this->position;
        return true;
    }

    private function literal(): object
    {
        $token = $this->take();
        if ($token[0] === "'") {
            return (object)['type' => 'string', 'value' => substr($token, 1, -1)];
        }
        return in_array($token, ['TRUE', 'FALSE'], true)
            ? (object)['type' => 'boolean', 'value' => $token === 'TRUE']
            : (object)['type' => 'integer', 'value' => (int)$token];
    }

    private function comparison(): object
    {
        $name = $this->take();
        $operator = $this->take();
        $literals = [];
        if ($operator === 'IS') {
            $operator = $this->accept('NOT') ? 'IS NOT NULL' : 'IS NULL';
            $this->take();
        } elseif ($operator === 'BETWEEN') {
            $literals[] = $this->literal();
            $this->take();
            $literals[] = $this->literal();
        } elseif ($operator === 'IN') {
            $this->take();
            do {
                $literals[] = $this->literal();
            } while ($this->accept(','));
            $this->take();
        } else {
            $literals[] = $this->literal();
        }
        return (object)['kind' => 'comparison', 'name' => $name, 'operator' => $operator, 'literals' => $literals];
    }

    private function negation(): object
    {
        if ($this->accept('NOT')) {
            return (object)['kind' => 'NOT', 'child' => $this->negation()];
        }
        if ($this->accept('(')) {
            $condition = $this->condition();
            $this->take();
            return $condition;
        }
        return $this->comparison();
    }

    private function conjunction(): object
    {
        $left = $this->negation();
        while ($this->accept('AND')) {
            $left = (object)['kind' => 'AND', 'left' => $left, 'right' => $this->negation()];
        }
        return $left;
    }

    private function condition(): object
    {
        $left = $this->conjunction();
        while ($this->accept('OR')) {
            $left = (object)['kind' => 'OR', 'left' => $left, 'right' => $this->conjunction()];
        }
        return $left;
    }

    private function item(): object
    {
        $token = $this->take();
        if (!$this->accept('(')) {
            return (object)['kind' => 'column', 'name' => $token];
        }
        $distinct = $this->accept('DISTINCT');
        $name = $this->take();
        $this->take();
        return (object)['kind' => 'aggregate', 'function' => $token, 'name' => $name === '*' ? null : $name, 'distinct' => $distinct];
    }

    public function parse(): object
    {
        $this->take();
        $items = [];
        $star = $this->accept('*');
        if (!$star) {
            do {
                $items[] = $this->item();
            } while ($this->accept(','));
        }
        $result = (object)['star' => $star, 'items' => $items, 'condition' => null, 'group' => null, 'order' => null, 'limit' => null];
        if ($this->accept('WHERE')) {
            $result->condition = $this->condition();
        }
        if ($this->accept('GROUP')) {
            $this->take();
            $result->group = $this->take();
        }
        if ($this->accept('ORDER')) {
            $this->take();
            $name = $this->take();
            $descending = $this->accept('DESC');
            if (!$descending) {
                $this->accept('ASC');
            }
            $result->order = (object)['name' => $name, 'descending' => $descending];
        }
        if ($this->accept('LIMIT')) {
            $result->limit = (int)$this->take();
        }
        return $result;
    }
}
