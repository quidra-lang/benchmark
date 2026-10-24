import type { Channel } from './channels.ts';
import type { ServerSettings } from './types.ts';

export class Client {
  id: string;
  host: string;
  connectionTime: number;
  nickname: string | null;
  username: string | null;
  realName: string;
  invisible: boolean;
  registered: boolean;
  registrationTime: number | null;
  lastReceived: number;
  lastSpeaking: number | null;
  pingSent: boolean;
  pingTime: number | null;
  tokens: number;
  refillTime: number | null;
  queue: string[];
  channels: Channel[];
  invites: Channel[];
  away: string;
  received: number;
  sent: number;
  active: boolean;

  constructor(id: string, host: string, time: number, bucket: number) {
    this.id = id;
    this.host = host;
    this.connectionTime = time;
    this.nickname = null;
    this.username = null;
    this.realName = '';
    this.invisible = false;
    this.registered = false;
    this.registrationTime = null;
    this.lastReceived = time;
    this.lastSpeaking = null;
    this.pingSent = false;
    this.pingTime = null;
    this.tokens = bucket;
    this.refillTime = null;
    this.queue = [];
    this.channels = [];
    this.invites = [];
    this.away = '';
    this.received = 0;
    this.sent = 0;
    this.active = true;
  }

  addressee(): string {
    return this.nickname === null ? '*' : this.nickname;
  }

  prefix(): string {
    return `${this.nickname}!${this.username}@${this.host}`;
  }

  mode(): string {
    return this.invisible ? '+i' : '+';
  }

  useToken(time: number, settings: ServerSettings): void {
    if (this.tokens === settings.BUCKET) this.refillTime = time + settings.REFILL;
    this.tokens--;
  }

  refill(time: number, settings: ServerSettings): void {
    if (this.refillTime !== time) return;
    this.tokens++;
    this.refillTime = this.tokens < settings.BUCKET ? time + settings.REFILL : null;
  }
}

