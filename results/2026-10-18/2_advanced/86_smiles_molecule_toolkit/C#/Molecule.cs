global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.IO;
global using System.Linq;
global using System.Text;
global using Elements = System.Collections.Generic.Dictionary<string, Element>;
sealed record Element(int Number, int Mass, List<int> Valences);
sealed record Atom(string Element, bool Aromatic = false, int Mass = 0, int Charge = 0, int Hydrogens = 0, bool Bracket = false, int Column = 1);
sealed record Bond
{
    public int A {
        get;
        set;
    }
    public int B {
        get;
        set;
    }
    public int Kind {
        get;
        set;
    }
    public int Multiplicity {
        get;
        set;
    }
    public bool Ring {
        get;
        set;
    }
    public Bond(int a, int b, int kind) {
        A = a;
        B = b;
        Kind = kind;
    }
}
sealed class MoleculeError(string reason, int column) : Exception(reason)
{
    public string Reason {
        get;
    } = reason;
    public int Column {
        get;
    } = column;
}
sealed class Molecule
{
    public List<Atom> Atoms {
        get;
    } = new();
    public List<Bond> Bonds {
        get;
    } = new();
    public List<List<(int Atom, int Bond)>> Neighbors {
        get;
        private set;
    } = new();
    public List<List<int>> Rings {
        get;
        set;
    } = new();
    public static Elements ReadElements() => File.ReadLines("input/elements.txt").Where(l => l.Length > 0 && !l.StartsWith('#')).Select(l => l.Split(' ')).ToDictionary(a => a[0], a => new Element(int.Parse(a[1]), int.Parse(a[2]), a[3].Split(',').Select(int.Parse).ToList()), StringComparer.Ordinal);
    public void Rebuild()
    {
        Bonds.Sort((a, b) => a.A != b.A ? a.A.CompareTo(b.A) : a.B.CompareTo(b.B));
        Neighbors = Enumerable.Range(0, Atoms.Count).Select(_ => new List<(int Atom, int Bond)>()).ToList();
        for (int i = 0; i < Bonds.Count; i++)
        {
            Bond b = Bonds[i];
            Neighbors[b.A].Add((b.B, i));
            Neighbors[b.B].Add((b.A, i));
        }
        foreach (var neighbors in Neighbors) neighbors.Sort((a, b) => a.Atom.CompareTo(b.Atom));
    }
    public int? BondIndex(int a, int b)
    {
        foreach (var neighbor in Neighbors[a]) if (neighbor.Atom == b) return neighbor.Bond;
        return null;
    }
    public int Base(int i) => Neighbors[i].Sum(n => Bonds[n.Bond].Kind == 4 ? 1 : Bonds[n.Bond].Kind);
    public int Multiplicity(int i) => Neighbors[i].Sum(n => Bonds[n.Bond].Multiplicity);
    public bool NeedsPi(int i, Elements elements, bool hydrogens)
    {
        Atom atom = Atoms[i];
        return atom.Aromatic && elements[atom.Element].Valences[0] + atom.Charge >= Base(i) + (hydrogens ? atom.Hydrogens : 0) + 1;
    }
    public int? OrganicHydrogens(int i, Elements elements)
    {
        int total = Multiplicity(i);
        foreach (int valence in elements[Atoms[i].Element].Valences) if (valence >= total) return valence - total;
        return null;
    }
}
