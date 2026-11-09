using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Predictors {
    public sealed class BTB {
        public int[] pcs, targets;
        public BTB(int entries) {
            pcs = new int[entries];
            targets = new int[entries];
            Array.Fill(pcs, -1);
        }
        public int Lookup(int pc) {
            int i = pc / 4 % pcs.Length;
            return pcs[i] == pc ? targets[i] : -1;
        }
        public void Insert(int pc, int target) {
            int i = pc / 4 % pcs.Length;
            pcs[i] = pc;
            targets[i] = target;
        }
    }
    public sealed class RAS {
        public int depth;
        public List<int> stack = new();
        public RAS(int depth) {
            this.depth = depth;
        }
        public void Push(int address) {
            if (depth == 0)
                return;
            if (stack.Count == depth)
                stack.RemoveAt(0);
            stack.Add(address);
        }
        public int Pop() {
            if (stack.Count == 0)
                return -1;
            int value = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            return value;
        }
    }
    public static int Updated(int counter, bool taken) {
        return taken ? Math.Min(3, counter + 1) : Math.Max(0, counter - 1);
    }
    public sealed class Direction {
        public string scheme;
        public int[] parameters, table, local, global, chooser;
        public int history;
        public Direction(TraceIO.Predictor definition) {
            scheme = definition.scheme;
            parameters = definition.parameters;
            if (scheme.Equals("TOURNAMENT")) {
                local = Ones(parameters[0]);
                global = Ones(parameters[1]);
                chooser = Ones(parameters[3]);
            } else if (parameters.Length > 0) {
                table = Ones(parameters[0]);
                if (scheme.Equals("ONEBIT"))
                    Array.Fill(table, 0);
            }
        }
        public static int[] Ones(int size) {
            int[] a = new int[size];
            Array.Fill(a, 1);
            return a;
        }
        public bool Prediction(int pc, int target) {
            int q = pc / 4;
            return scheme switch { "STATIC_NT" or "PERFECT" => false,
                                   "BTFN" => target < pc,
                                   "ONEBIT" => table[q % table.Length] == 1,
                                   "TWOBIT" => table[q % table.Length] >= 2,
                                   "GSHARE" => table[(q ^ history) % table.Length] >= 2,
                                   _ => chooser[q % chooser.Length] >= 2
                                            ? global[(q ^ history) % global.Length] >= 2
                                            : local[q % local.Length] >= 2 };
        }
        public void Update(int pc, bool taken) {
            int q = pc / 4;
            if (scheme.Equals("TOURNAMENT")) {
                int l = q % local.Length, g = (q ^ history) % global.Length, c = q % chooser.Length;
                bool lp = local[l] >= 2, gp = global[g] >= 2;
                if (lp != gp)
                    chooser[c] = Updated(chooser[c], gp == taken);
                local[l] = Updated(local[l], taken);
                global[g] = Updated(global[g], taken);
                history = (2 * history + (taken ? 1 : 0)) % (1 << parameters[2]);
            } else if (table != null) {
                int i = (scheme.Equals("GSHARE") ? q ^ history : q) % table.Length;
                table[i] = scheme.Equals("ONEBIT") ? (taken ? 1 : 0) : Updated(table[i], taken);
                if (scheme.Equals("GSHARE"))
                    history = (2 * history + (taken ? 1 : 0)) % (1 << parameters[1]);
            }
        }
        public int Bits() {
            return scheme switch {
                "ONEBIT" => parameters[0],
                "TWOBIT" => 2 * parameters[0],
                "GSHARE" => 2 * parameters[0] + parameters[1],
                "TOURNAMENT" => 2 * (parameters[0] + parameters[1] + parameters[3]) + parameters[2],
                _ => 0,
            };
        }
    }
}
