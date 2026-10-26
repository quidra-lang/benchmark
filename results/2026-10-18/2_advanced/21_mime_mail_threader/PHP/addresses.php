<?php
declare(strict_types=1);

namespace MailThreads;

final class AddressError extends \RuntimeException {}
final class Mailbox
{
    public function __construct(public string $name, public string $address) {}
}
final class Group
{
    public function __construct(public array $mailboxes) {}
}

function isDotAtom(array $tokens): bool
{
    if (count($tokens) % 2 === 0) {
        return false;
    }
    foreach ($tokens as $index => $token) {
        if ($token->kind !== ($index % 2 === 0 ? 'word' : '.')) {
            return false;
        }
    }
    return true;
}

function addressString(array $local, array $domain): string
{
    if (!isDotAtom($local) || !isDotAtom($domain)) {
        throw new AddressError();
    }
    $first = implode('', array_map(static fn(Token $token): string => $token->text, $local));
    $second = implode('', array_map(static fn(Token $token): string => $token->text, $domain));
    return strtolower($first . '@' . $second);
}

final class AddressParser
{
    private int $position = 0;
    public bool $encodingError = false;

    public function __construct(private array $tokens) {}
    private function peek(): ?string { return $this->tokens[$this->position]->kind ?? null; }

    private function expect(string $kind): void
    {
        if ($this->peek() !== $kind) {
            throw new AddressError();
        }
        $this->position++;
    }

    private function readRun(array $kinds): array
    {
        $start = $this->position;
        while (in_array($this->peek(), $kinds, true)) {
            $this->position++;
        }
        return array_slice($this->tokens, $start, $this->position - $start);
    }

    private function displayName(array $phrase): string
    {
        $parts = [];
        $previous = false;
        foreach ($phrase as $index => $token) {
            $text = $token->text;
            $decoded = false;
            if ($token->kind === 'word') {
                [$text, $decoded, $failed] = decodeWord($text);
                $this->encodingError = $this->encodingError || $failed;
            }
            if ($index > 0 && $token->spaced && !($decoded && $previous)) {
                $parts[] = ' ';
            }
            $parts[] = $text;
            $previous = $decoded;
        }
        return collapseWhitespace(implode('', $parts));
    }

    private function parseAddress(bool $inGroup): Mailbox|Group
    {
        $phrase = $this->readRun(['word', 'quoted', '.']);
        $following = $this->peek();
        if ($following === '<') {
            $this->position++;
            $local = $this->readRun(['word', '.']);
            $this->expect('@');
            $domain = $this->readRun(['word', '.']);
            $this->expect('>');
            return new Mailbox($this->displayName($phrase), addressString($local, $domain));
        }
        if ($following === '@') {
            $this->position++;
            return new Mailbox('', addressString($phrase, $this->readRun(['word', '.'])));
        }
        if ($following === ':' && $phrase !== [] && !$inGroup) {
            $this->position++;
            $mailboxes = [];
            if ($this->peek() !== ';') {
                $mailboxes[] = $this->parseAddress(true);
                while ($this->peek() === ',') {
                    $this->position++;
                    $mailboxes[] = $this->parseAddress(true);
                }
            }
            $this->expect(';');
            return new Group($mailboxes);
        }
        throw new AddressError();
    }

    public function parseList(): array
    {
        $addresses = [$this->parseAddress(false)];
        while ($this->peek() === ',') {
            $this->position++;
            $addresses[] = $this->parseAddress(false);
        }
        if ($this->position !== count($this->tokens)) {
            throw new AddressError();
        }
        return $addresses;
    }
}

function parseAddressList(string $value): ?array
{
    $tokens = tokenizeAddress($value);
    if ($tokens === null || $tokens === []) {
        return null;
    }
    $parser = new AddressParser($tokens);
    try {
        $addresses = $parser->parseList();
        return [$addresses, $parser->encodingError];
    } catch (AddressError) {
        return null;
    }
}
