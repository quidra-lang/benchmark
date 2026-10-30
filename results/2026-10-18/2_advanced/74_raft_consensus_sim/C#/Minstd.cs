using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public sealed class Minstd {
    public long state;
    public int draws;
    public Minstd(int seed) { state = seed; }
    public int Draw() {
        state = 48271 * state % 2147483647;
        draws++;
        return (int)state;
    }
    public int Between(int minimum, int maximum) {
        return minimum + Draw() % (maximum - minimum + 1);
    }
}
