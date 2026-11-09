sealed record Parsed(Molecule Molecule, List<Matcher> Matchers);
sealed record OpenRing(int Atom, (int Kind, int Column)? Symbol, int Column);
static class SmilesParser
{
    public static (string Element, bool Aromatic, int Length)? Organic(string text)
    {
        if (text.StartsWith("Cl", StringComparison.Ordinal)) return ("Cl", false, 2);
        if (text.StartsWith("Br", StringComparison.Ordinal)) return ("Br", false, 2);
        if (text.Length == 0) return null;
        char c = text[0];
        if ("BCNOPSFI".Contains(c)) return (c.ToString(), false, 1);
        if ("bcnops".Contains(c)) return (char.ToUpperInvariant(c).ToString(), true, 1);
        return null;
    }
    public static (Atom Atom, int Length) ParseAtom(string text, int column, Elements elements)
    {
        if (text[0] != '[')
        {
            var (element, aromatic, n) = Organic(text) ?? throw new MoleculeError("unexpected character", column);
            return (new Atom(element, aromatic, Column: column), n);
        }
        int end = text.IndexOf(']');
        if (end < 0) throw new MoleculeError("unclosed bracket", column);
        string s = text[1..end];
        int i = 0;
        while (i < s.Length && s[i] is >= '0' and <= '9') i++;
        if (i >= 4 || i > 0 && s[0] == '0') throw new MoleculeError("bad bracket atom", column);
        int mass = i == 0 ? 0 : int.Parse(s[..i], CultureInfo.InvariantCulture);
        if (i == s.Length) throw new MoleculeError("bad bracket atom", column);
        string symbol;
        bool aromaticAtom;
        if ("bcnops".Contains(s[i])) {
            symbol = char.ToUpperInvariant(s[i]).ToString();
            aromaticAtom = true;
            i++;
        }
        else if (s[i] is >= 'A' and <= 'Z')
        {
            string one = s[i].ToString();
            if (i + 1 < s.Length && s[i + 1] is >= 'a' and <= 'z' && elements.ContainsKey(s.Substring(i, 2))) {
                symbol = s.Substring(i, 2);
                i += 2;
            }
            else if (elements.ContainsKey(one)) {
                symbol = one;
                i++;
            }
            else throw new MoleculeError("unknown element", column);
            aromaticAtom = false;
        }
        else throw new MoleculeError("bad bracket atom", column);
        if (i < s.Length && s[i] == '@') {
            i++;
            if (i < s.Length && s[i] == '@') i++;
        }
        int hydrogens = 0;
        if (i < s.Length && s[i] == 'H')
        {
            hydrogens = 1;
            i++;
            if (i < s.Length && s[i] is >= '0' and <= '9') {
                hydrogens = s[i] - '0';
                i++;
            }
        }
        int charge = 0;
        if (i < s.Length && s[i] is '+' or '-')
        {
            int sign = s[i] == '+' ? 1 : -1;
            i++;
            int amount = 1;
            if (i < s.Length && s[i] is >= '1' and <= '9') {
                amount = s[i] - '0';
                i++;
            }
            charge = sign * amount;
        }
        if (i != s.Length) throw new MoleculeError("bad bracket atom", column);
        return (new Atom(symbol, aromaticAtom, mass, charge, hydrogens, true, column), end + 1);
    }
    public static int? Symbol(char c, bool pattern) => c switch
    {
        '-' => 1, '=' => 2, '#' => 3, ':' => 4, '~' => pattern ? 5 : null, '/' or '\\' => pattern ? null : 1, _ => null
    };
    public static Parsed Parse(string text, Elements elements, bool pattern = false)
    {
        Molecule molecule = new();
        List<Matcher> matchers = new();
        int? current = null;
        (int Kind, int Column)? pending = null;
        List<(int Atom, int Column)> branches = new();
        Dictionary<int, OpenRing> rings = new();
        int i = 0;
        void Add(int a, int b, int kind) => molecule.Bonds.Add(new Bond(Math.Min(a, b), Math.Max(a, b), kind));
        while (i < text.Length)
        {
            char c = text[i];
            int column = i + 1;
            if (Symbol(c, pattern) is {
            } kind)
            {
                if (current is null || pending is not null) throw new MoleculeError("misplaced bond", column);
                pending = (kind, column);
                i++;
            }
            else if (c == '(')
            {
                if (current is null || pending is not null || i > 0 && text[i - 1] == '(') throw new MoleculeError("misplaced branch", column);
                branches.Add((current.Value, column));
                i++;
            }
            else if (c == ')')
            {
                if (branches.Count == 0) throw new MoleculeError("unmatched parenthesis", column);
                if (pending is {
                } p) throw new MoleculeError("dangling bond", p.Column);
                if (i > 0 && text[i - 1] == '(') throw new MoleculeError("empty branch", column);
                current = branches[^1].Atom;
                branches.RemoveAt(branches.Count - 1);
                i++;
            }
            else if (c is >= '0' and <= '9' || c == '%')
            {
                int atom = current ?? throw new MoleculeError("misplaced ring closure", column);
                int number;
                if (c == '%')
                {
                    if (i + 2 >= text.Length || text[i + 1] is < '0' or > '9' || text[i + 2] is < '0' or > '9') throw new MoleculeError("bad ring number", column);
                    number = int.Parse(text.Substring(i + 1, 2), CultureInfo.InvariantCulture);
                    i += 3;
                }
                else {
                    number = c - '0';
                    i++;
                }
                var closing = pending;
                pending = null;
                if (rings.Remove(number, out OpenRing? opening))
                {
                    if (opening.Atom == atom) throw new MoleculeError("self bond", column);
                    if (opening.Symbol is {
                    } first && closing is {
                    } last && first.Kind != last.Kind) throw new MoleculeError("ring bond mismatch", column);
                    if (molecule.Bonds.Any(b => b.A == Math.Min(opening.Atom, atom) && b.B == Math.Max(opening.Atom, atom))) throw new MoleculeError("duplicate bond", column);
                    Add(opening.Atom, atom, (closing ?? opening.Symbol)?.Kind ?? 0);
                }
                else rings[number] = new OpenRing(atom, closing, column);
            }
            else
            {
                Atom atom;
                int length;
                if (pattern)
                {
                    var (matcher, n) = Search.PatternAtom(text[i..], column);
                    matchers.Add(matcher);
                    atom = new Atom("", Column: column);
                    length = n;
                }
                else (atom, length) = ParseAtom(text[i..], column, elements);
                int next = molecule.Atoms.Count;
                molecule.Atoms.Add(atom);
                if (current is {
                } previous) Add(previous, next, pending?.Kind ?? 0);
                current = next;
                pending = null;
                i += length;
            }
        }
        if (pending is {
        } dangling) throw new MoleculeError("dangling bond", dangling.Column);
        if (branches.Count > 0) throw new MoleculeError("unmatched parenthesis", branches[0].Column);
        if (rings.Count > 0) throw new MoleculeError("unclosed ring", rings.Values.Min(r => r.Column));
        molecule.Rebuild();
        return new Parsed(molecule, matchers);
    }
}
