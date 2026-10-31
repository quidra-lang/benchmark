using System.Collections.Generic;
public static class Clients {
    public sealed class Client {
        public readonly string identifier, hostname;
        public readonly int connectionTime;
        public string nickname, username, realname = "", away = "";
        public bool invisible, registered, active = true;
        public int registrationTime = -1, lastReceived, lastSpeaking = -1, pingSent = -1, tokens,
                   refillTime = -1, received, sent;
        public Queue<string> queue = new();
        public List<Channels.Channel> channels = new(), invites = new();
        public Client(string identifier, string hostname, int time, int capacity) {
            this.identifier = identifier;
            this.hostname = hostname;
            connectionTime = lastReceived = time;
            tokens = capacity;
        }
        public string addressee => nickname ?? "*";
        public string prefix => nickname + "!" + username + "@" + hostname;
        public string mode => invisible ? "+i" : "+";
        public void UseToken(int time, int capacity, int interval) {
            if (tokens == capacity)
                refillTime = time + interval;
            tokens--;
        }
        public void Refill(int time, int capacity, int interval) {
            if (refillTime == time) {
                tokens++;
                refillTime = tokens < capacity ? time + interval : -1;
            }
        }
    }
}
