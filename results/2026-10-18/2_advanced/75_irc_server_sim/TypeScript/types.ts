import type { Client } from './clients.ts';
import type { Channel, Ban } from './channels.ts';

export interface ServerSettings {
  NAME: string;
  VERSION: string;
  CREATED: string;
  DESCRIPTION: string;
  NICKLEN: number;
  CHANNELLEN: number;
  TOPICLEN: number;
  MAXCHANNELS: number;
  BUCKET: number;
  REFILL: number;
  QUEUE: number;
  PINGFREQ: number;
  TIMEOUT: number;
  MOTD: string[];
}

export type TrafficKind = 'connect' | 'disconnect' | 'messages';
export interface TrafficRecord {
  time: number;
  id: string;
  body: string;
  kind: TrafficKind;
}

export type DisconnectionKind = 'quit' | 'closed' | 'flood' | 'timeout';

export interface NumericContext {
  target?: string;
  channel?: Channel;
  user?: Client;
  command?: string;
  character?: string;
  ban?: Ban;
  names?: string;
  motd?: string;
}
