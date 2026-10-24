export interface Settings {
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

export type DisconnectKind = 'quit' | 'closed' | 'flood' | 'timeout';
