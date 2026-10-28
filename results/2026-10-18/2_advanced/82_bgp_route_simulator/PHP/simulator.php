<?php

final readonly class Message
{
    public function __construct(
        public int $serial,
        public int $sender,
        public int $receiver,
        public Link $link,
        public string $prefix,
        public ?RouteAttributes $content,
        public int $arrival,
    ) {}

    public function priority(): array
    {
        return [-$this->arrival, -$this->receiver, -$this->sender, -$this->serial];
    }
}

final class MessageQueue
{
    private SplPriorityQueue $heap;
    private int $serial = 0;

    public function __construct()
    {
        $this->heap = new SplPriorityQueue();
        $this->heap->setExtractFlags(SplPriorityQueue::EXTR_DATA);
    }

    public function send(
        int $time,
        int $sender,
        int $receiver,
        Link $link,
        string $prefix,
        ?RouteAttributes $content,
    ): Message {
        $m = new Message(++$this->serial, $sender, $receiver, $link, $prefix, $content, $time + $link->delay);
        $this->heap->insert($m, $m->priority());
        return $m;
    }

    public function nextTime(): ?int
    {
        return $this->heap->isEmpty() ? null : $this->heap->top()->arrival;
    }

    public function take(): Message
    {
        return $this->heap->extract();
    }

    public function ordered(): array
    {
        $copy = clone $this->heap;
        $messages = [];
        while (!$copy->isEmpty())
            $messages[] = $copy->extract();
        return $messages;
    }

    public function removeLink(Link $link): array
    {
        $removed = [];
        $keep = new SplPriorityQueue();
        $keep->setExtractFlags(SplPriorityQueue::EXTR_DATA);
        foreach ($this->ordered() as $m)
            if ($m->link === $link)
                $removed[] = $m;
            else
                $keep->insert($m, $m->priority());
        $this->heap = $keep;
        return $removed;
    }

    public function state(int $time): array
    {
        return array_map(fn($m) => [
            $m->arrival - $time,
            $m->receiver,
            $m->sender,
            $m->link->number,
            $m->prefix,
            $m->content,
        ], $this->ordered());
    }
}

function readEvents(): array
{
    $events = [(object) ['time' => 0, 'text' => 'INITIAL', 'fields' => ['INITIAL'], 'kind' => 'INITIAL']];
    foreach (file('input/events.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$time, $text] = explode(' ', $line, 2);
        $f = explode(' ', $text);
        $kind = in_array($f[0], ['LINK', 'POLICY'], true) ? $f[0] . '_' . $f[1] : $f[0];
        $events[] = (object) ['time' => (int) $time, 'text' => $text, 'fields' => $f, 'kind' => $kind];
    }
    return $events;
}

function readParams(): array
{
    $lines = file('input/params.txt', FILE_IGNORE_NEW_LINES);
    $f = explode(' ', $lines[0]);
    $defaults = ['customer' => (int) $f[1], 'peer' => (int) $f[2], 'provider' => (int) $f[3]];
    $stepcap = (int) explode(' ', $lines[1])[1];
    $traces = [];
    foreach (array_slice($lines, 2) as $line) {
        [, $source, $address] = explode(' ', $line);
        $traces[] = [(int) $source, $address, addressValue($address)];
    }
    return [$defaults, $stepcap, $traces];
}
