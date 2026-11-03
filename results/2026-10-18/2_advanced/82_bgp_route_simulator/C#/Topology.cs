using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Linq;
public sealed class Topology {
    public record Prefix(long address, int length) : IComparable<Prefix> {
        public int CompareTo(Prefix other) {
            int c = address.CompareTo(other.address);
            return c != 0 ? c : length.CompareTo(other.length);
        }
        public override string ToString() => AddressText(address) + "/" + length;
        public bool Contains(long value) {
            int shift = 32 - length;
            return address >> shift == value >> shift;
        }
    }
    public static long AddressValue(string text) {
        long value = 0;
        foreach (string octet in text.Split('.'))
            value = (value << 8) + int.Parse(octet);
        return value;
    }
    public static string AddressText(long value) => ((value >> 24) & 255) + "." +
                                                    ((value >> 16) & 255) + "." +
                                                    ((value >> 8) & 255) + "." + (value & 255);
    public static Prefix ParsePrefix(string text) {
        string[] f = text.Split('/');
        return new(AddressValue(f[0]), int.Parse(f[1]));
    }
    public sealed class Link {
        public int number, first, second, delay, mrai, downCount;
        public string name, relationship;
        public bool up = true;
        public Link(int number, string[] f) {
            this.number = number;
            name = f[1];
            first = int.Parse(f[2]);
            second = int.Parse(f[3]);
            relationship = f[4];
            delay = int.Parse(f[5]);
            mrai = int.Parse(f[6]);
        }
        public int Other(int owner) => owner == first ? second : first;
        public string Role(int owner) => relationship == "P2P" ? "peer"
                                         : owner == first      ? "customer"
                                                               : "provider";
        public char Direction(int owner) => Role(owner) switch { "customer" => 'D', "peer" => 'P',
                                                                 _ => 'U' };
    }
    public record Initial(int owner, Prefix prefix, string origin,
                          List<Policy.Community> communities);
    public SortedDictionary<int, long> routerIds = new();
    public List<Link> links = new();
    public Dictionary<string, Link> byName = new();
    public SortedDictionary<int, List<Link>> atAs = new();
    public List<Initial> initial = new();
    public Topology() {
        foreach (string line in File.ReadAllLines("input/topology.txt", Encoding.ASCII)) {
            string[] f = line.Split(' ');
            if (f[0] == "AS")
                routerIds[int.Parse(f[1])] = AddressValue(f[2]);
            else if (f[0] == "LINK") {
                Link link = new(links.Count, f);
                links.Add(link);
                byName[link.name] = link;
            } else
                initial.Add(
                    new(int.Parse(f[1]), ParsePrefix(f[2]), f[3], Policy.Communities(f.Skip(4))));
        }
        foreach (int owner in routerIds.Keys)
            atAs[owner] = new();
        foreach (Link link in links) {
            atAs[link.first].Add(link);
            atAs[link.second].Add(link);
        }
    }
    public Link Connecting(int first,
                           int second) => atAs[first].First(link => link.Other(first) == second);
}
