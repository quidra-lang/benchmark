using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Minstd {
    private long state;
    public Minstd(int seed) {
        state = seed;
    }
    public int Draw() {
        state = state * 48271 % 2147483647;
        return (int)state;
    }
    public int Below(int limit) {
        return Draw() % limit;
    }
    public bool Chance(int[] fraction) {
        return Draw() % fraction[1] < fraction[0];
    }
    public void Shuffle(List<int> sequence) {
        for (int length = sequence.Count; length >= 2; length--)
            Program.Swap(sequence, length - 1, Below(length));
    }
}
