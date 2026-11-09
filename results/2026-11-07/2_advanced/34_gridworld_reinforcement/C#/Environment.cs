using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Environment {
    public sealed class Rng {
        public long state;
        public Rng(long seed) {
            state = seed;
        }
        public long Draw() {
            state = state * 48271 % 2147483647;
            return state;
        }
    }
    public sealed record Outcome(int cell, int weight);
    public readonly int height, width, size, start;
    public readonly char[] cells;
    public readonly int[] states, terminals, wind;
    public readonly long[] rewards;
    public readonly int[][] moves;
    public Environment(long stepReward) {
        List<string> lines = File.ReadAllLines(Path.Combine("input/world.txt"), Encoding.ASCII).ToList();
        height = int.Parse(lines[0].Split(" ")[1]);
        width = int.Parse(lines[1].Split(" ")[1]);
        size = height * width;
        cells = new char[size];
        rewards = new long[size];
        wind = new int[width];
        moves = Enumerable.Range(0, size)
                    .Select(
                        _ => new int[4])
                    .ToArray();
        List<int> active = new(), ends = new();
        int origin = -1;
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int x = r * width + c;
                cells[x] = lines[r + 2][c];
                rewards[x] = stepReward;
                if (cells[x] == 'G' || cells[x] == 'P')
                    ends.Add(x);
                else if (cells[x] != '#')
                    active.Add(x);
                if (cells[x] == 'S')
                    origin = x;
            }
        start = origin;
        states = active.ToArray();
        terminals = ends.ToArray();
        string winds = lines[height + 2].Split(" ")[1];
        for (int c = 0; c < width; c++)
            wind[c] = winds[c] - '0';
        string[] values = lines[height + 3].Split(" ");
        for (int i = 0; i < terminals.Length; i++)
            rewards[terminals[i]] = long.Parse(values[i + 1]);
        int[] offsets = { -width, 1, width, -1 };
        foreach (int x in states)
            for (int action = 0; action < 4; action++) {
                int y = x + offsets[action];
                if (cells[y] == '#')
                    y = x;
                if (!Terminal(y))
                    for (int i = 0; i < wind[x % width]; i++) {
                        if (cells[y - width] == '#')
                            break;
                        y -= width;
                        if (Terminal(y))
                            break;
                    }
                moves[x][action] = y;
            }
    }
    public bool Terminal(int x) {
        return cells[x] == 'G' || cells[x] == 'P';
    }
    public sealed class Model {
        public readonly Environment world;
        public readonly int q, floorSlip, iceSlip;
        public readonly List<Outcome>[][] transitions;
        public Model(Environment world, int q, int floorSlip, int iceSlip) {
            this.world = world;
            this.q = q;
            this.floorSlip = floorSlip;
            this.iceSlip = iceSlip;
            transitions = Enumerable.Range(0, world.size)
                              .Select(
                                  _ => new List<Outcome>[4])
                              .ToArray();
            foreach (int x in world.states)
                for (int a = 0; a < 4; a++) {
                    List<Outcome> row = new();
                    int p = Slip(x);
                    int[] directions = { a, (a + 1) % 4, (a + 3) % 4 }, weights = { q - 2 * p, p, p };
                    for (int i = 0; i < 3; i++)
                        if (weights[i] > 0)
                            row.Add(new Outcome(world.moves[x][directions[i]], weights[i]));
                    transitions[x][a] = row;
                }
        }
        public int Slip(int x) {
            return world.cells[x] == '~' ? iceSlip : floorSlip;
        }
        public int Step(int x, int action, Rng rng) {
            long t = rng.Draw() % q;
            int p = Slip(x);
            int direction = t < q - 2 * p ? action : t < q - p ? (action + 1) % 4 : (action + 3) % 4;
            return world.moves[x][direction];
        }
    }
}
