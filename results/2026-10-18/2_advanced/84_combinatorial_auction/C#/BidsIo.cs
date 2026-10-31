using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
public sealed class BidsIo {
    public record Item(string name, long reserve);
    public record Bid(int number, int bidder, int bundle, long amount, bool xor) {
        public int Size() => BitOperations.PopCount((uint)bundle);
    }
    public record Participant(string name, long value, long bid);
    public record BidderLine(string name, string language, List<string> bids);
    public sealed class RawAuction {
        public string name;
        public List<string> items;
        public List<BidderLine> lines = new();
        public RawAuction(string name, List<string> items) {
            this.name = name;
            this.items = items;
        }
    }
    public sealed class Group {
        public string kind, name;
        public List<string> arguments;
        public List<Participant> participants = new();
        public Group(string[] f) {
            kind = f[0];
            name = f[1];
            arguments = f.Skip(2).ToList();
        }
    }
    public List<Item> items = new();
    public Dictionary<string, RawAuction> auctions = new();
    public List<Group> groups = new();
    public List<string> runs;
    public Dictionary<string, long> settings = new();
    public static string[] Lines(string name) => File.ReadAllLines(Path.Combine("input", name),
                                                                   Encoding.ASCII);
    public BidsIo() {
        foreach (string line in Lines("items.txt")) {
            string[] f = line.Split(' ');
            items.Add(new(f[0], long.Parse(f[1])));
        }
        RawAuction auction = null;
        foreach (string line in Lines("bids.txt")) {
            string[] f = line.Split(' ');
            if (f[0] == "auction") {
                auction = new(f[1], f.Skip(2).ToList());
                auctions[f[1]] = auction;
            } else
                auction.lines.Add(new(f[1], f[2], f.Skip(3).ToList()));
        }
        Group group = null;
        foreach (string line in Lines("single_item.txt")) {
            string[] f = line.Split(' ');
            if (f[0] == "lot" || f[0] == "slots") {
                group = new(f);
                groups.Add(group);
            } else
                group.participants.Add(new(f[1], long.Parse(f[2]), long.Parse(f[3])));
        }
        foreach (string line in Lines("params.txt")) {
            string[] f = line.Split(' ');
            if (f[0] == "run")
                runs = f.Skip(1).ToList();
            else
                settings[f[0]] = long.Parse(f[1]);
        }
    }
}
