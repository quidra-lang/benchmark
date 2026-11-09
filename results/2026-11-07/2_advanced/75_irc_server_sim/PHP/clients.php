<?php

class Client
{
    public string $id;
    public string $host;
    public int $connectionTime;
    public ?string $nickname = null;
    public ?string $username = null;
    public string $realName = '';
    public bool $invisible = false;
    public bool $registered = false;
    public ?int $registrationTime = null;
    public int $lastReceived;
    public ?int $lastSpeaking = null;
    public bool $pingSent = false;
    public ?int $pingTime = null;
    public int $tokens;
    public ?int $refillTime = null;
    public array $queue = [];
    public array $channels = [];
    public array $invites = [];
    public string $away = '';
    public int $received = 0;
    public int $sent = 0;
    public bool $active = true;

    public function __construct(string $id, string $host, int $time, int $bucket)
    {
        $this->id = $id;
        $this->host = $host;
        $this->connectionTime = $this->lastReceived = $time;
        $this->tokens = $bucket;
    }

    public function addressee(): string { return $this->nickname ?? '*'; }
    public function prefix(): string { return $this->nickname . '!' . $this->username . '@' . $this->host; }
    public function mode(): string { return $this->invisible ? '+i' : '+'; }

    public function useToken(int $time, array $settings): void
    {
        if ($this->tokens === $settings['BUCKET']) $this->refillTime = $time + $settings['REFILL'];
        $this->tokens--;
    }

    public function refill(int $time, array $settings): void
    {
        if ($this->refillTime !== $time) return;
        $this->tokens++;
        $this->refillTime = $this->tokens < $settings['BUCKET'] ? $time + $settings['REFILL'] : null;
    }
}
