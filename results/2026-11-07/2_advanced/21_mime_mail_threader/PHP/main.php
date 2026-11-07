<?php
declare(strict_types=1);

namespace MailThreads;

require_once __DIR__ . '/mime.php';
require_once __DIR__ . '/headers.php';
require_once __DIR__ . '/addresses.php';
require_once __DIR__ . '/dates.php';
require_once __DIR__ . '/threader.php';

const CHECKED_FIELDS = ['From', 'To', 'Cc', 'Subject', 'Date', 'Message-ID', 'In-Reply-To', 'References', 'MIME-Version', 'Content-Type', 'Content-Transfer-Encoding', 'Content-Disposition'];
const ID_FORBIDDEN = '<>()"\\';
const IDENTITY_ENCODINGS = ['7bit', '8bit', 'binary'];
const HIDDEN_TAGS = ['head', 'style', 'script'];
const PARAGRAPH_TAGS = ['p', 'div', 'ul', 'ol', 'table', 'tr', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'];
const CHARACTER_REFERENCES = ['amp' => '&', 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'", 'nbsp' => ' '];

function readLines(string $path): array { return file($path, FILE_IGNORE_NEW_LINES); }

function readMailbox(string $path): array
{
    $messages = [];
    foreach (readLines($path) as $index => $line) {
        if (str_starts_with($line, 'From ')) {
            $messages[] = [];
        } elseif ($messages !== []) {
            if (preg_match('/\A>+From /', $line) === 1) {
                $line = substr($line, 1);
            }
            $messages[count($messages) - 1][] = [$index + 1, $line];
        }
    }
    foreach ($messages as $index => $lines) {
        if ($lines !== [] && $lines[count($lines) - 1][1] === '') {
            array_pop($messages[$index]);
        }
    }
    return $messages;
}

function splitSections(array $lines): array
{
    foreach ($lines as $index => [$_, $text]) {
        if ($text === '') {
            return [array_slice($lines, 0, $index), array_slice($lines, $index + 1)];
        }
    }
    return [$lines, []];
}

function isMessageId(string $text): bool
{
    if (strlen($text) < 3 || !str_starts_with($text, '<') || !str_ends_with($text, '>')) {
        return false;
    }
    $inside = substr($text, 1, -1);
    if (substr_count($inside, '@') !== 1 || str_starts_with($inside, '@') || str_ends_with($inside, '@')) {
        return false;
    }
    for ($position = 0; $position < strlen($inside); $position++) {
        $code = ord($inside[$position]);
        if ($code < 33 || $code > 126 || str_contains(ID_FORBIDDEN, $inside[$position])) {
            return false;
        }
    }
    return true;
}

function extractIds(string $value): array
{
    $ids = [];
    $position = 0;
    while (($start = strpos($value, '<', $position)) !== false) {
        $end = strpos($value, '>', $start + 1);
        if ($end === false) {
            break;
        }
        $id = substr($value, $start, $end - $start + 1);
        if (isMessageId($id)) {
            $ids[] = $id;
        }
        $position = $end + 1;
    }
    return $ids;
}

function dateNotation(?int $seconds): string { return $seconds === null ? 'invalid' : formatUtc($seconds); }
function subjectNotation(string $subject): string { return $subject === '' ? '(no subject)' : $subject; }

final class Entity
{
    public string $mainType = 'text';
    public string $subtype = 'plain';
    public array $parameters = [];
    public ?string $disposition = null;
    public ?string $filename = null;
    public ?array $children = null;
    public string $content = '';
    public function __construct(public string $number) {}
    public function parameter(string $name): string { return $this->parameters['#' . $name] ?? ''; }
}

final class Message
{
    public array $problems = [];
    public ?Mailbox $sender = null;
    public array $to = [];
    public array $cc = [];
    public string $subject = '';
    public string $baseSubject = '';
    public bool $reply = false;
    public ?int $date = null;
    public string $id = '';
    public array $references = [];
    public Entity $body;
    public array $sortKey;
    public int $thread = 0;
    public int $depth = 0;
    public ?self $parent = null;
    public function __construct(public int $number) {}
    public function problem(string $text): void { $this->problems[] = $text; }

    private function readSender(?string $value): void
    {
        if ($value === null) {
            $this->problem('missing From');
            return;
        }
        $parsed = parseAddressList($value);
        if ($parsed === null || count($parsed[0]) !== 1 || $parsed[0][0] instanceof Group) {
            $this->problem('bad From');
            return;
        }
        [$addresses, $encodingError] = $parsed;
        $this->sender = $addresses[0];
        if ($encodingError) {
            $this->problem('bad encoded word in From');
        }
    }

    private function readRecipients(?string $value, string $name): array
    {
        if ($value === null) {
            return [];
        }
        $parsed = parseAddressList($value);
        if ($parsed === null) {
            $this->problem('bad ' . $name);
            return [];
        }
        [$addresses, $encodingError] = $parsed;
        $recipients = [];
        foreach ($addresses as $address) {
            if ($address instanceof Group) {
                foreach ($address->mailboxes as $mailbox) {
                    $recipients[] = $mailbox->address;
                }
            } else {
                $recipients[] = $address->address;
            }
        }
        if ($encodingError) {
            $this->problem('bad encoded word in ' . $name);
        }
        return $recipients;
    }

    private function parseEntity(string $number, Header $header, array $lines, bool $enabled): Entity
    {
        $entity = new Entity($number);
        $contentType = $header->value('Content-Type');
        if ($enabled && $contentType !== null) {
            $parsed = parseParameters($contentType, true);
            if ($parsed === null) {
                $this->problem('bad Content-Type in part ' . $number);
            } else {
                [$entity->mainType, $entity->subtype, $entity->parameters] = $parsed;
            }
        }
        $disposition = $header->value('Content-Disposition');
        if ($enabled && $disposition !== null) {
            $parsed = parseParameters($disposition, false);
            if ($parsed === null) {
                $this->problem('bad Content-Disposition in part ' . $number);
            } else {
                $entity->disposition = $parsed[0];
                $entity->filename = $parsed[2]['#filename'] ?? null;
            }
        }
        if ($entity->filename === null || $entity->filename === '') {
            $entity->filename = $entity->parameters['#name'] ?? null;
        }
        $charset = $entity->parameters['#charset'] ?? null;
        if ($entity->mainType === 'text' && $charset !== null && strtolower($charset) !== 'us-ascii') {
            $this->problem('unsupported charset "' . strtolower($charset) . '" in part ' . $number);
        }
        if ($enabled && $entity->mainType === 'multipart') {
            $boundary = $entity->parameter('boundary');
            if ($boundary !== '') {
                $parts = [];
                $closed = false;
                foreach ($lines as $line) {
                    $text = rtrim($line[1], " \t");
                    if ($text === '--' . $boundary . '--') {
                        $closed = true;
                        break;
                    }
                    if ($text === '--' . $boundary) {
                        $parts[] = [];
                    } elseif ($parts !== []) {
                        $parts[count($parts) - 1][] = $line;
                    }
                }
                if ($parts === []) {
                    $this->problem('no parts in part ' . $number);
                } elseif (!$closed) {
                    $this->problem('unterminated multipart in part ' . $number);
                }
                $entity->children = [];
                foreach ($parts as $index => $part) {
                    [$headerLines, $bodyLines] = splitSections($part);
                    $childHeader = parseFields($headerLines);
                    foreach ($childHeader->invalidLines as $lineNumber) {
                        $this->problem('bad header line ' . $lineNumber);
                    }
                    $entity->children[] = $this->parseEntity($number . '.' . ($index + 1), $childHeader, $bodyLines, true);
                }
                return $entity;
            }
            $this->problem('missing boundary in part ' . $number);
        }
        $original = implode("\n", array_column($lines, 1));
        $transfer = $header->value('Content-Transfer-Encoding');
        $encoding = $enabled && $transfer !== null ? strtolower($transfer) : '7bit';
        if ($encoding === 'base64') {
            $content = decodeBase64Body($original);
            if ($content === null) {
                $this->problem('bad base64 in part ' . $number);
                $content = '';
            }
        } elseif ($encoding === 'quoted-printable') {
            [$content, $error] = decodeQuotedPrintable($original);
            if ($error) {
                $this->problem('bad quoted-printable in part ' . $number);
            }
        } else {
            $content = $original;
            if (!in_array($encoding, IDENTITY_ENCODINGS, true)) {
                $this->problem('unknown encoding "' . $encoding . '" in part ' . $number);
            }
        }
        $entity->content = $content;
        return $entity;
    }

    public function process(array $lines, array &$knownIds): void
    {
        [$headerLines, $bodyLines] = splitSections($lines);
        $header = parseFields($headerLines);
        foreach ($header->invalidLines as $lineNumber) {
            $this->problem('bad header line ' . $lineNumber);
        }
        foreach (CHECKED_FIELDS as $name) {
            if ($header->count($name) > 1) {
                $this->problem('duplicate ' . $name);
            }
        }
        $this->readSender($header->value('From'));
        $this->to = $this->readRecipients($header->value('To'), 'To');
        $this->cc = $this->readRecipients($header->value('Cc'), 'Cc');
        [$this->subject, $encodingError] = decodeUnstructured($header->value('Subject') ?? '');
        if ($encodingError) {
            $this->problem('bad encoded word in Subject');
        }
        $this->baseSubject = $this->subject;
        while (strtolower(substr($this->baseSubject, 0, 3)) === 're:') {
            $this->baseSubject = ltrim(substr($this->baseSubject, 3), ' ');
            $this->reply = true;
        }
        $date = $header->value('Date');
        if ($date === null) {
            $this->problem('missing Date');
        } else {
            try {
                $this->date = parseDate($date);
            } catch (DateError $error) {
                $this->problem($error->getMessage());
            }
        }
        $id = $header->value('Message-ID');
        if ($id === null) {
            $this->problem('missing Message-ID');
        } elseif (!isMessageId($id)) {
            $this->problem('bad Message-ID');
        } elseif (isset($knownIds['#' . $id])) {
            $this->problem('Message-ID already used by message ' . $knownIds['#' . $id]);
        } else {
            $this->id = $id;
            $knownIds['#' . $id] = $this->number;
        }
        $this->references = extractIds($header->value('References') ?? '');
        $replies = extractIds($header->value('In-Reply-To') ?? '');
        if ($replies !== [] && ($this->references === [] || $this->references[count($this->references) - 1] !== $replies[0])) {
            $this->references[] = $replies[0];
        }
        $version = $header->value('MIME-Version');
        $enabled = false;
        if ($version !== null) {
            $text = removeComments($version);
            if ($text !== null && str_replace([" ", "\t"], '', $text) === '1.0') {
                $enabled = true;
            } else {
                $this->problem('bad MIME-Version');
            }
        }
        $this->body = $this->parseEntity('1', $header, $bodyLines, $enabled);
        $this->sortKey = [$this->date === null ? 1 : 0, $this->date ?? 0, $this->id, $this->number];
    }
}

function collectTextParts(Entity $entity, bool $allowHtml): array
{
    if ($entity->children === null) {
        if ($entity->disposition === 'attachment' || $entity->mainType !== 'text') {
            return [];
        }
        return $entity->subtype === 'plain' || $entity->subtype === 'html' && $allowHtml ? [$entity] : [];
    }
    if ($entity->subtype === 'alternative') {
        foreach ([false, true] as $htmlPass) {
            foreach ($entity->children as $child) {
                $parts = collectTextParts($child, $htmlPass);
                if ($parts !== []) {
                    return $parts;
                }
            }
        }
        return [];
    }
    $parts = [];
    foreach ($entity->children as $child) {
        array_push($parts, ...collectTextParts($child, $allowHtml));
    }
    return $parts;
}

function quotePrefix(int $depth): string { return $depth > 0 ? str_repeat('>', $depth) . ' ' : ''; }
function wrapText(string $text, string $prefix): array
{
    $lines = [];
    $current = '';
    foreach (splitWords($text) as $word) {
        if ($current !== '' && strlen($current) + 1 + strlen($word) > 72) {
            $lines[] = $prefix . $current;
            $current = $word;
        } elseif ($current !== '') {
            $current .= ' ' . $word;
        } else {
            $current = $word;
        }
    }
    $lines[] = $prefix . $current;
    return $lines;
}

final class LogicalLine
{
    public function __construct(public int $depth, public string $text, public bool $flowing = false) {}
}

function flowedLines(string $content, bool $deleteSpace): array
{
    if ($content === '') {
        return [];
    }
    $logical = [];
    foreach (explode("\n", $content) as $line) {
        $text = ltrim($line, '>');
        $depth = strlen($line) - strlen($text);
        if (str_starts_with($text, ' ')) {
            $text = substr($text, 1);
        }
        $flowing = str_ends_with($text, ' ') && $text !== '-- ';
        $previous = $logical === [] ? null : $logical[count($logical) - 1];
        if ($previous !== null && $previous->flowing && $previous->depth === $depth) {
            if ($deleteSpace) {
                $previous->text = substr($previous->text, 0, -1);
            }
            $previous->text .= $text;
            $previous->flowing = $flowing;
        } else {
            $logical[] = new LogicalLine($depth, $text, $flowing);
        }
    }
    $lines = [];
    foreach ($logical as $line) {
        array_push($lines, ...wrapText($line->text, quotePrefix($line->depth)));
    }
    return $lines;
}

function replaceReferences(string $text): string
{
    $result = '';
    $position = 0;
    while ($position < strlen($text)) {
        $replacement = null;
        $end = false;
        if ($text[$position] === '&') {
            $end = strpos($text, ';', $position + 1);
            if ($end !== false) {
                $name = substr($text, $position + 1, $end - $position - 1);
                $replacement = CHARACTER_REFERENCES[$name] ?? null;
                if ($replacement === null && preg_match('/\A#[0-9]{1,3}\z/', $name) === 1) {
                    $code = (int)substr($name, 1);
                    if ($code >= 32 && $code <= 126) {
                        $replacement = chr($code);
                    }
                }
            }
        }
        if ($replacement !== null) {
            $result .= $replacement;
            $position = $end + 1;
        } else {
            $result .= $text[$position++];
        }
    }
    return $result;
}

function htmlLines(string $content): array
{
    $blocks = [];
    $depth = 0;
    $text = '';
    $hide = null;
    $position = 0;
    while ($position < strlen($content)) {
        $char = $content[$position];
        $close = $char === '<' ? strpos($content, '>', $position + 1) : false;
        if ($close === false) {
            if ($hide === null) {
                $text .= $char;
            }
            $position++;
            continue;
        }
        $inside = substr($content, $position + 1, $close - $position - 1);
        $position = $close + 1;
        $endTag = str_starts_with($inside, '/');
        preg_match('/\A[A-Za-z0-9]*/', $endTag ? substr($inside, 1) : $inside, $match);
        $name = strtolower($match[0]);
        if ($hide !== null) {
            if ($endTag && $name === $hide) {
                $hide = null;
            }
        } elseif (!$endTag && in_array($name, HIDDEN_TAGS, true)) {
            $hide = $name;
        } elseif ($name === 'br' || $name === 'li' && !$endTag) {
            $blocks[] = new LogicalLine($depth, $text);
            $text = $name === 'li' ? '* ' : '';
        } elseif (in_array($name, PARAGRAPH_TAGS, true)) {
            $blocks[] = new LogicalLine($depth, $text);
            $blocks[] = new LogicalLine($depth, '');
            $text = '';
            if ($name === 'blockquote') {
                $depth = $endTag ? max($depth - 1, 0) : $depth + 1;
            }
        }
    }
    $blocks[] = new LogicalLine($depth, $text);
    $lines = [];
    foreach ($blocks as $block) {
        $normalized = collapseWhitespace(str_replace("\n", ' ', $block->text));
        $normalized = trim(replaceReferences($normalized), ' ');
        if ($normalized !== '') {
            array_push($lines, ...wrapText($normalized, quotePrefix($block->depth)));
        } elseif ($lines !== [] && $lines[count($lines) - 1] !== '') {
            $lines[] = '';
        }
    }
    while ($lines !== [] && $lines[count($lines) - 1] === '') {
        array_pop($lines);
    }
    return $lines;
}

function displayLines(Entity $entity): array
{
    if ($entity->subtype === 'html') {
        return ['html', htmlLines($entity->content)];
    }
    if (strtolower($entity->parameter('format')) === 'flowed') {
        return ['flowed', flowedLines($entity->content, strtolower($entity->parameter('delsp')) === 'yes')];
    }
    return ['plain', $entity->content === '' ? [] : explode("\n", $entity->content)];
}

function containerNotation(Container $container): string
{
    $message = $container->message;
    if ($message !== null) {
        return '[' . $message->number . '] ' . dateNotation($message->date) . ' ' . ($message->sender?->address ?? '-') . ' ' . subjectNotation($message->subject);
    }
    return $container->subject !== null ? '[subject] ' . $container->subject : '[missing] ' . $container->id;
}

final class Thread
{
    public array $entries = [];
    public array $messages = [];

    public function __construct(public int $number, public Container $root)
    {
        $this->walk($root, '', '', 0);
    }

    private function walk(Container $container, string $prefix, string $stem, int $depth): void
    {
        $this->entries[] = [$container, $prefix, $depth];
        if ($container->message !== null) {
            $message = $container->message;
            $message->thread = $this->number;
            $message->depth = $depth;
            $message->parent = $container->parent?->message;
            $this->messages[] = $message;
        }
        foreach ($container->children as $index => $child) {
            $last = $index + 1 === count($container->children);
            $this->walk($child, $stem . ($last ? '`- ' : '+- '), $stem . ($last ? '   ' : '|  '), $depth + 1);
        }
    }

    public function report(): array
    {
        $depth = 0;
        foreach ($this->entries as [$_, $prefix, $ownDepth]) {
            $depth = max($depth, $ownDepth);
        }
        $senders = [];
        $first = $last = null;
        foreach ($this->messages as $message) {
            if ($message->sender !== null) {
                $senders['#' . $message->sender->address] = true;
            }
            if ($message->date !== null) {
                $first = $first === null ? $message->date : min($first, $message->date);
                $last = $last === null ? $message->date : max($last, $message->date);
            }
        }
        $subject = $this->root->subject ?? rootSubject($this->root);
        $lines = [
            'thread ' . $this->number . ' messages ' . count($this->messages) . ' depth ' . $depth . ' senders ' . count($senders),
            $first === null ? 'span -' : 'span ' . formatUtc($first) . ' .. ' . formatUtc($last),
            'subject ' . subjectNotation($subject),
        ];
        foreach ($this->entries as [$container, $prefix, $_]) {
            $lines[] = $prefix . containerNotation($container);
        }
        return $lines;
    }
}

function entityLines(Entity $entity, array &$lines): void
{
    $line = 'part ' . $entity->number . ' ' . $entity->mainType . '/' . $entity->subtype;
    if ($entity->children !== null) {
        $lines[] = $line;
        foreach ($entity->children as $child) {
            entityLines($child, $lines);
        }
        return;
    }
    $line .= ' ' . strlen($entity->content);
    if ($entity->disposition !== null) {
        $line .= ' ' . $entity->disposition;
    }
    if ($entity->filename !== null && $entity->filename !== '') {
        $line .= ' "' . $entity->filename . '"';
    }
    $lines[] = $line;
}

function messageReport(Message $message): array
{
    $sender = '-';
    if ($message->sender !== null) {
        $sender = $message->sender->address;
        if ($message->sender->name !== '') {
            $sender = $message->sender->name . ' <' . $sender . '>';
        }
    }
    $parent = $message->parent?->number ?? '-';
    $lines = [
        'message ' . $message->number,
        'id ' . ($message->id === '' ? '-' : $message->id),
        'date ' . dateNotation($message->date),
        'from ' . $sender,
        'to ' . ($message->to === [] ? '-' : implode(', ', $message->to)),
        'cc ' . ($message->cc === [] ? '-' : implode(', ', $message->cc)),
        'subject ' . subjectNotation($message->subject),
        'refs ' . ($message->references === [] ? '-' : implode(' ', $message->references)),
        "thread {$message->thread} depth {$message->depth} parent {$parent}",
    ];
    entityLines($message->body, $lines);
    return $lines;
}

function bodyReport(string $request, array $byId): array
{
    $lines = ['request ' . $request];
    $message = $byId['#' . $request] ?? null;
    if ($message === null) {
        $lines[] = 'not found';
        return $lines;
    }
    $parts = collectTextParts($message->body, true);
    $lines[] = 'message ' . $message->number . ' text parts ' . count($parts);
    foreach ($parts as $part) {
        [$format, $display] = displayLines($part);
        $quoted = $signature = 0;
        foreach ($display as $index => $line) {
            $line = rtrim($line, " \t");
            $quoted += (int)str_starts_with($line, '>');
            if ($line === '--') {
                $signature = count($display) - $index - 1;
            }
        }
        $lines[] = "part {$part->number} {$format} lines " . count($display) . " quoted {$quoted} signature {$signature}";
        foreach ($display as $line) {
            $line = rtrim($line, " \t");
            $lines[] = $line === '' ? '|' : '| ' . $line;
        }
    }
    return $lines;
}

final class SenderStats
{
    public int $count = 0;
    public array $threads = [];
    public ?int $first = null;
    public ?int $last = null;
    public string $name = '';
    public function __construct(public string $address) {}

    public function add(Message $message): void
    {
        $this->count++;
        $this->threads[$message->thread] = true;
        if ($message->date !== null) {
            $this->first = $this->first === null ? $message->date : min($this->first, $message->date);
            $this->last = $this->last === null ? $message->date : max($this->last, $message->date);
        }
        if ($message->sender->name !== '') {
            $this->name = $message->sender->name;
        }
    }
}

function csvField(string $text): string
{
    return str_contains($text, ',') || str_contains($text, '"') ? '"' . str_replace('"', '""', $text) . '"' : $text;
}

function sendersReport(array $messages): array
{
    $stats = [];
    foreach ($messages as $message) {
        if ($message->sender === null) {
            continue;
        }
        $address = $message->sender->address;
        $stats['#' . $address] ??= new SenderStats($address);
        $stats['#' . $address]->add($message);
    }
    $ordered = array_values($stats);
    usort($ordered, static fn(SenderStats $a, SenderStats $b): int => ($b->count <=> $a->count) ?: strcmp($a->address, $b->address));
    $lines = ['address,name,messages,threads,first,last'];
    foreach ($ordered as $entry) {
        $first = $entry->first === null ? '-' : formatUtc($entry->first);
        $last = $entry->last === null ? '-' : formatUtc($entry->last);
        $lines[] = $entry->address . ',' . csvField($entry->name) . ',' . $entry->count . ',' . count($entry->threads) . ',' . $first . ',' . $last;
    }
    return $lines;
}

function malformedReport(array $messages): array
{
    $flagged = $total = 0;
    foreach ($messages as $message) {
        $flagged += (int)($message->problems !== []);
        $total += count($message->problems);
    }
    $lines = ['messages ' . count($messages) . " malformed {$flagged} problems {$total}"];
    foreach ($messages as $message) {
        foreach ($message->problems as $problem) {
            $lines[] = 'message ' . $message->number . ': ' . $problem;
        }
    }
    return $lines;
}

function joinBlocks(array $blocks): array
{
    $lines = [];
    foreach ($blocks as $block) {
        if ($lines !== []) {
            $lines[] = '';
        }
        array_push($lines, ...$block);
    }
    return $lines;
}

function writeOutput(string $name, array $lines): void
{
    $lines = array_map(static fn(string $line): string => rtrim($line, " \t"), $lines);
    file_put_contents('output/' . $name, $lines === [] ? '' : implode("\n", $lines) . "\n");
}

function main(): void
{
    $messages = $knownIds = [];
    foreach (readMailbox('input/mailbox.mbox') as $index => $lines) {
        $message = new Message($index + 1);
        $message->process($lines, $knownIds);
        $messages[] = $message;
    }
    $threads = [];
    foreach (buildThreads($messages) as $index => $root) {
        $threads[] = new Thread($index + 1, $root);
    }
    $byId = [];
    foreach ($messages as $message) {
        $parent = $message->parent;
        if ($parent !== null && $message->date !== null && $parent->date !== null && $message->date < $parent->date) {
            $message->problem('dated before parent message ' . $parent->number);
        }
        if ($message->id !== '') {
            $byId['#' . $message->id] = $message;
        }
    }
    $threadBlocks = $messageBlocks = $bodyBlocks = [];
    foreach ($threads as $thread) {
        $threadBlocks[] = $thread->report();
    }
    foreach ($messages as $message) {
        $messageBlocks[] = messageReport($message);
    }
    foreach (readLines('input/requests.txt') as $request) {
        $bodyBlocks[] = bodyReport($request, $byId);
    }
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    writeOutput('threads.txt', joinBlocks($threadBlocks));
    writeOutput('messages.txt', joinBlocks($messageBlocks));
    writeOutput('bodies.txt', joinBlocks($bodyBlocks));
    writeOutput('senders.csv', sendersReport($messages));
    writeOutput('malformed.txt', malformedReport($messages));
}

main();
