<?php
class Parser {
    public function __construct(private array $tokens, private array $variables, private int $position) {}
    private function factor(): int {
        $token = $this->tokens[$this->position++];
        if ($token === '-') return -$this->factor();
        if ($token === '(') {
            $value = $this->expression();
            $this->position++;
            return $value;
        }
        if (ctype_digit($token)) return (int)$token;
        if (!array_key_exists($token,$this->variables)) throw new RuntimeException('undefined variable '.$token);
        return $this->variables[$token];
    }
    private function term(): int {
        $value = $this->factor();
        while (isset($this->tokens[$this->position]) && in_array($this->tokens[$this->position],['*','/'],true)) {
            $operation = $this->tokens[$this->position++];
            $right = $this->factor();
            if ($operation === '/' && $right === 0) throw new RuntimeException('division by zero');
            $value = $operation === '*' ? $value*$right : intdiv($value,$right);
        }
        return $value;
    }
    public function expression(): int {
        $value = $this->term();
        while (isset($this->tokens[$this->position]) && in_array($this->tokens[$this->position],['+','-'],true)) {
            $operation = $this->tokens[$this->position++];
            $right = $this->term();
            $value = $operation === '+' ? $value+$right : $value-$right;
        }
        return $value;
    }
}
$lines = ['width = 12','height = width - 5','area = width * height','(area + 6) / 4','shift = -area / 8 + 3','height = 100 / (height - 7) + bonus','volume = area * depth','width = (width+3)*-(2-4)','width * shift - height'];
$variables = [];
foreach ($lines as $line) {
    preg_match_all('/[0-9]+|[a-z]+|[()+*\/=-]/',$line,$matches);
    $tokens = $matches[0];
    $assignment = isset($tokens[1]) && $tokens[1] === '=';
    try {
        $parser = new Parser($tokens,$variables,$assignment ? 2 : 0);
        $value = $parser->expression();
        if ($assignment) {
            $variables[$tokens[0]] = $value;
            printf("%s = %d\n",$tokens[0],$value);
        } else printf("%d\n",$value);
    } catch (RuntimeException $error) {
        echo 'error: ', $error->getMessage(), "\n";
    }
}
