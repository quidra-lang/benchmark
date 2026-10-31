<?php

function privilege(object $member): string
{
    return $member->operator ? '@' : ($member->voice ? '+' : '');
}

class Channel
{
    public string $name;
    public int $creationTime;
    public array $members = [];
    public string $topic = '';
    public ?string $topicSetter = null;
    public ?int $topicTime = null;
    public array $bans = [];
    public array $flags = ['n' => true, 't' => true];
    public string $key = '';
    public int $limit = 0;
    public int $peak = 0;
    public int $messages = 0;

    public function __construct(string $name, int $time)
    {
        $this->name = $name;
        $this->creationTime = $time;
    }

    public function member(Client $client): ?object
    {
        foreach ($this->members as $member) if ($member->client === $client) return $member;
        return null;
    }

    public function add(Client $client): void
    {
        $operator = count($this->members) === 0;
        $this->members[] = (object) ['client' => $client, 'operator' => $operator, 'voice' => false];
        $client->channels[] = $this;
        $this->peak = max($this->peak, count($this->members));
    }

    public function remove(Client $client): bool
    {
        foreach ($this->members as $index => $member) {
            if ($member->client === $client) { array_splice($this->members, $index, 1); break; }
        }
        $index = array_search($this, $client->channels, true);
        array_splice($client->channels, $index, 1);
        return count($this->members) === 0;
    }

    public function nameList(?Client $viewer = null): string
    {
        $includeInvisible = $viewer === null || $this->member($viewer) !== null;
        $names = [];
        foreach ($this->members as $member) {
            if ($includeInvisible || !$member->client->invisible) $names[] = privilege($member) . $member->client->nickname;
        }
        return implode(' ', $names);
    }

    public function labelFor(Client $client): string
    {
        return privilege($this->member($client)) . $this->name;
    }

    public function banned(Client $client): bool
    {
        foreach ($this->bans as $ban) if (maskMatches($ban->mask, $client->prefix())) return true;
        return false;
    }

    public function canSpeak(Client $client): bool
    {
        $member = $this->member($client);
        $privileged = $member !== null && ($member->operator || $member->voice);
        return ($member !== null || !isset($this->flags['n']))
            && (!isset($this->flags['m']) || $privileged)
            && ($privileged || !$this->banned($client));
    }

    public function modeDisplay(bool $includeKey): string
    {
        $display = '+';
        foreach (str_split('iklmnt') as $character) {
            $present = $character === 'k' ? $this->key !== ''
                : ($character === 'l' ? $this->limit !== 0 : isset($this->flags[$character]));
            if ($present) $display .= $character;
        }
        if ($includeKey && $this->key !== '') $display .= ' ' . $this->key;
        if ($this->limit !== 0) $display .= ' ' . $this->limit;
        return $display;
    }
}
