using System;
using System.Collections.Generic;
using System.Text;
public static class Channels {
    public sealed class Member {
        public Clients.Client client;
        public bool op, voice;
        public Member(Clients.Client client, bool op) {
            this.client = client;
            this.op = op;
        }
        public string status => op ? "@" : voice ? "+" : "";
        public string display => status + client.nickname;
    }
    public record Ban(string mask, string setter, int time);
    public sealed class Channel {
        public string name, topic = "", topicSetter, key = "";
        public int created, topicTime = -1, limit, peak, messages;
        public List<Member> members = new();
        public List<Ban> bans = new();
        public HashSet<char> flags = new() { 'n', 't' };
        public Channel(string name, int time) {
            this.name = name;
            created = time;
        }
        public Member FindMember(Clients.Client client) {
            foreach (Member member in members)
                if (member.client == client)
                    return member;
            return null;
        }
        public Member Add(Clients.Client client, bool op) {
            Member member = new(client, op);
            members.Add(member);
            client.channels.Add(this);
            peak = Math.Max(peak, members.Count);
            return member;
        }
        public void Remove(Clients.Client client) {
            members.Remove(FindMember(client));
            client.channels.Remove(this);
        }
        public string NameList(Clients.Client viewer) {
            bool inside = FindMember(viewer) != null;
            List<string> names = new();
            foreach (Member member in members)
                if (inside || !member.client.invisible)
                    names.Add(member.display);
            return string.Join(" ", names);
        }
        public bool Banned(Clients.Client client) {
            foreach (Ban ban in bans)
                if (Masks.Matches(ban.mask, client.prefix))
                    return true;
            return false;
        }
        public bool CanSpeak(Clients.Client client) {
            Member member = FindMember(client);
            bool privileged = member != null && (member.op || member.voice);
            return (member != null || !flags.Contains('n')) &&
                   (!flags.Contains('m') || privileged) && (privileged || !Banned(client));
        }
        public string ModeDisplay(bool includeKey) {
            StringBuilder mode = new("+");
            foreach (char c in "iklmnt")
                if (c == 'k' ? key.Length != 0 : c == 'l' ? limit != 0 : flags.Contains(c))
                    mode.Append(c);
            if (includeKey && key.Length != 0)
                mode.Append(" ").Append(key);
            if (limit != 0)
                mode.Append(" ").Append(limit);
            return mode.ToString();
        }
    }
}
