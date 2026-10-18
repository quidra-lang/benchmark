import { readFileSync } from "node:fs";

type ArgKind = string | [number, number | "n", boolean?];
type Orf = {left: number; right: number; frame: number; protein: string};
type Repeat = {position: number; width: number; count: number; unit: string};
const BASES = "ACGT";
const IUPAC: Record<string, string> = {
  A: "A", C: "C", G: "G", T: "T", R: "AG", Y: "CT", W: "AT", S: "CG",
  K: "GT", M: "AC", B: "CGT", D: "AGT", H: "ACT", V: "ACG", N: "ACGT"
};
const SYMBOL: Record<string, string> = Object.fromEntries(Object.entries(IUPAC).map(([s, b]) => [b, s]));
const COMPLEMENT: Record<string, string> = Object.fromEntries([..."ACGTRYWSKMBVDHN"].map((c, i) => [c, "TGCAYRWSMKVBHDN"[i]]));
const GROUPS: Record<string, string> = {
  A: "GCT GCC GCA GCG", C: "TGT TGC", D: "GAT GAC", E: "GAA GAG", F: "TTT TTC",
  G: "GGT GGC GGA GGG", H: "CAT CAC", I: "ATT ATC ATA", K: "AAA AAG",
  L: "TTA TTG CTT CTC CTA CTG", M: "ATG", N: "AAT AAC", P: "CCT CCC CCA CCG",
  Q: "CAA CAG", R: "CGT CGC CGA CGG AGA AGG", S: "TCT TCC TCA TCG AGT AGC",
  T: "ACT ACC ACA ACG", V: "GTT GTC GTA GTG", W: "TGG", Y: "TAT TAC", "*": "TAA TAG TGA"
};
const CODE: Record<string, string> = {};
for (const [amino, codons] of Object.entries(GROUPS)) {
  for (const codon of codons.split(" ")) CODE[codon] = amino;
}
const AMINO_VALUES = [71079, 103139, 115089, 129116, 147177, 57052, 137141, 113160, 128174, 113160, 131193, 114104, 97117, 128131, 156188, 87078, 101105, 99133, 186213, 163176];
const AMINO_MASS: Record<string, number> = Object.fromEntries([..."ACDEFGHIKLMNPQRSTVWY"].map((a, i) => [a, AMINO_VALUES[i]]));
const BASE_MASS: Record<string, number> = {A: 331222, C: 307197, G: 347221, T: 322208};
const ENZYMES: Record<string, [string, number]> = {
  EcoRI: ["GAATTC", 1], BamHI: ["GGATCC", 1], HindIII: ["AAGCTT", 1],
  PstI: ["CTGCAG", 5], SmaI: ["CCCGGG", 3], KpnI: ["GGTACC", 5],
  XbaI: ["TCTAGA", 1], NotI: ["GCGGCCGC", 2], EcoRV: ["GATATC", 3],
  HaeIII: ["GGCC", 2], AluI: ["AGCT", 2], TaqI: ["TCGA", 1],
  Sau3AI: ["GATC", 0], HincII: ["GTYRAC", 3], AvaI: ["CYCGRG", 1]
};
const ARITY: Record<string, number[]> = {
  SEQ: [2, 2], SLICE: [4, 4], JOIN: [3, 9], MUTATE: [3, 3], DEL: [1, 1],
  LIST: [0, 0], REVCOMP: [1, 1], COMPLEMENT: [1, 1], REVERSE: [1, 1],
  TRANSCRIBE: [1, 1], TRANSLATE: [2, 2], CODONS: [2, 2], PROTEIN: [2, 2],
  ORFS: [2, 2], GC: [1, 1], GCWINDOW: [3, 3], SKEW: [1, 1], KMERS: [3, 3],
  FIND: [2, 2], RESTRICT: [2, 7], PALINDROMES: [3, 3], REPEATS: [4, 4],
  HAMMING: [2, 2], ALIGN: [6, 6], CONSENSUS: [2, 10], TM: [1, 1],
  MASS: [1, 1], PRIMER: [1, 1], FOLD: [2, 2], ASSEMBLE: [4, 10],
  PACK: [1, 1], UNPACK: [3, 3]
};
class CommandError extends Error {}
const lex = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const revcomp = (s: string): string => [...s].reverse().map(b => COMPLEMENT[b]).join("");
const gc = (s: string): number => [...s].filter(b => b === "G" || b === "C").length;
const fixed = (v: number, places: number): string => Math.floor(v / 10 ** places) + "." + String(v % 10 ** places).padStart(places, "0");
const pct = (a: number, b: number): string => fixed(Math.floor(10000 * a / b), 2);
const transition = (a: string, b: string): boolean => ["AG", "GA", "CT", "TC"].includes(a + b);
const temperature = (s: string): number => s.length < 14 ? 10 * (2 * (s.length - gc(s)) + 4 * gc(s)) : Math.floor((649 * s.length + 410 * gc(s) - 6724) / s.length);
const strandMass = (s: string): number => [...s].reduce((total, b) => total + BASE_MASS[b], 0) - (s.length - 1) * 18015;

function counts(items: Iterable<string>): Map<string, number> {
  const table = new Map<string, number>();
  for (const item of items) table.set(item, (table.get(item) ?? 0) + 1);
  return table;
}

function frequencyOrder(table: Map<string, number>): string[] {
  return [...table.keys()].sort((a, b) => table.get(b)! - table.get(a)! || lex(a, b));
}

function codons(s: string, frame: number): string[] {
  const strand = frame > 0 ? s : revcomp(s);
  return strand.slice(Math.abs(frame) - 1).match(/.../g) ?? [];
}

function occurrences(s: string, motif: string): number[] {
  const result: number[] = [];
  for (let i = 0; i + motif.length <= s.length; i++) {
    if ([...motif].every((symbol, j) => IUPAC[symbol].includes(s[i + j]))) result.push(i + 1);
  }
  return result;
}

function repeatCount(s: string, start: number, width: number): number {
  const unit = s.slice(start, start + width);
  let count = 0;
  while (s.slice(start + count * width, start + (count + 1) * width) === unit) count++;
  return count;
}

function primitive(unit: string): boolean {
  for (let d = 1; d < unit.length; d++) {
    if (unit.length % d === 0 && unit.slice(0, d).repeat(unit.length / d) === unit) return false;
  }
  return true;
}

function longestPalindrome(s: string): number {
  let best = 0;
  for (let center = 1; center < s.length; center++) {
    let left = center - 1;
    let right = center;
    while (left >= 0 && right < s.length && COMPLEMENT[s[left]] === s[right]) {
      best = Math.max(best, right - left + 1);
      left--;
      right++;
    }
  }
  return best;
}

class Toolkit {
  registry = new Map<string, string>();
  output: string[] = [];

  emit(...parts: (string | number)[]): void {
    this.output.push(parts.join(" "));
  }

  emitList(label: string, values: (string | number)[]): void {
    this.emit(label, ...(values.length ? values : ["none"]));
  }

  kinds(cmd: string, count: number): ArgKind[] {
    switch (cmd) {
      case "SEQ": return ["new", "sequence"];
      case "SLICE": return ["name", [1, "n"], [1, "n"], "new"];
      case "JOIN": return ["new", ...Array(count - 1).fill("name")];
      case "MUTATE": return ["name", [1, "n"], "base"];
      case "TRANSLATE":
      case "CODONS":
      case "PROTEIN": return ["name", [-3, 3, true]];
      case "ORFS": return ["name", [1, 200]];
      case "GCWINDOW": return ["name", [1, 500], [1, 500]];
      case "KMERS": return ["name", [1, 12], [1, 100]];
      case "FIND": return ["name", "motif"];
      case "RESTRICT": return ["name", ...Array(count - 1).fill("enzyme")];
      case "PALINDROMES": return ["name", [2, 20], [2, 20]];
      case "REPEATS": return ["name", [1, 6], [1, 6], [2, 50]];
      case "ALIGN": return ["name", "name", "mode", [1, 20], [-20, 0], [-20, -1]];
      case "FOLD": return ["name", [0, 10]];
      case "ASSEMBLE": return ["new", [1, 100], ...Array(count - 2).fill("name")];
      case "UNPACK": return ["new", [1, 500], "hex"];
      default: return Array(count).fill("name");
    }
  }

  validate(cmd: string, a: string[]): void {
    if (!Object.hasOwn(ARITY, cmd)) throw new CommandError("unknown command " + cmd);
    const [minimum, maximum] = ARITY[cmd];
    if (a.length < minimum || a.length > maximum) throw new CommandError("wrong argument count");
    const kinds = this.kinds(cmd, a.length);
    const seen = new Set<string>();
    for (let i = 0; i < a.length; i++) {
      const text = a[i];
      const kind = kinds[i];
      if (Array.isArray(kind)) {
        const upper = kind[1] === "n" ? this.registry.get(a[0])!.length : kind[1];
        const value = Number(text);
        if (!/^-?[0-9]{1,6}$/.test(text) || value < kind[0] || value > upper || (kind[2] && value === 0)) throw new CommandError("invalid number " + text);
      } else if (kind === "name") {
        if (!this.registry.has(text)) throw new CommandError("unknown sequence " + text);
      } else if (kind === "new") {
        if (!/^[a-z][a-z0-9]{0,9}$/.test(text)) throw new CommandError("invalid name " + text);
      } else if (kind === "sequence") {
        for (let p = 0; p < text.length; p++) {
          if (!BASES.includes(text[p])) throw new CommandError("invalid base " + text[p] + " at " + (p + 1));
        }
      } else if (kind === "base") {
        if (text.length !== 1 || !BASES.includes(text)) throw new CommandError("invalid base " + text);
      } else if (kind === "motif") {
        if (text.length < 1 || text.length > 30 || [...text].some(c => !Object.hasOwn(IUPAC, c))) throw new CommandError("invalid motif " + text);
      } else if (kind === "enzyme") {
        if (!Object.hasOwn(ENZYMES, text)) throw new CommandError("unknown enzyme " + text);
        if (seen.has(text)) throw new CommandError("duplicate enzyme " + text);
        seen.add(text);
      } else if (kind === "mode") {
        if (!["GLOBAL", "LOCAL"].includes(text)) throw new CommandError("invalid mode " + text);
      } else if (kind === "hex") {
        if (!/^[0-9A-F]+$/.test(text) || text.length !== 2 * Math.ceil(Number(a[1]) / 4)) throw new CommandError("invalid hex");
      }
    }
  }

  store(name: string, s: string): string {
    if (s.length > 500) throw new CommandError("too long");
    const label = this.registry.has(name) ? "replaced" : "stored";
    this.registry.set(name, s);
    return label + " " + name + " " + s.length + " nt";
  }

  translation(cmd: string, s: string, frame: number): void {
    const triplets = codons(s, frame);
    let protein = triplets.map(c => CODE[c]).join("");
    if (cmd === "TRANSLATE") {
      this.emit(protein || "none");
    } else if (cmd === "CODONS") {
      const table = counts(triplets);
      for (const c of frequencyOrder(table)) this.emit(c, CODE[c], table.get(c)!);
      if (!table.size) this.emit("none");
    } else {
      protein = protein.split("*")[0];
      if (!protein) throw new CommandError("empty protein");
      const table = counts(protein);
      const mass = [...protein].reduce((v, amino) => v + AMINO_MASS[amino], 18015);
      const charge = [...protein].reduce((v, amino) => v + Number("KR".includes(amino)) - Number("DE".includes(amino)), 0);
      this.emit(protein);
      this.emit("length", protein.length, "mass", fixed(mass, 3), "charge", charge > 0 ? "+" + charge : charge);
      this.emit(...frequencyOrder(table).map(a => a + "=" + table.get(a)));
    }
  }

  orfs(s: string, minimum: number): void {
    const results: Orf[] = [];
    for (const frame of [1, 2, 3, -1, -2, -3]) {
      const triplets = codons(s, frame);
      let start: number | null = null;
      for (let p = 0; p < triplets.length; p++) {
        if (start === null) {
          if (triplets[p] === "ATG") start = p;
        } else if (CODE[triplets[p]] === "*") {
          if (p - start >= minimum) {
            let left = Math.abs(frame) - 1 + 3 * start;
            let right = Math.abs(frame) - 1 + 3 * (p + 1);
            if (frame < 0) [left, right] = [s.length - right, s.length - left];
            const protein = triplets.slice(start, p).map(c => CODE[c]).join("");
            results.push({left: left + 1, right, frame, protein});
          }
          start = null;
        }
      }
    }
    results.sort((a, b) => a.left - b.left);
    for (const r of results) this.emit(r.frame > 0 ? "+" + r.frame : r.frame, r.left, r.right, r.protein.length, r.protein);
    if (!results.length) this.emit("none");
  }

  restrict(s: string, enzymes: string[]): void {
    const combined = new Set<number>();
    for (const enzyme of enzymes) {
      const [motif, offset] = ENZYMES[enzyme];
      const cuts = occurrences(s, motif).map(p => p + offset - 1).filter(c => c >= 1 && c < s.length);
      this.emitList(enzyme, cuts);
      for (const c of cuts) combined.add(c);
    }
    const endpoints = [0, ...[...combined].sort((a, b) => a - b), s.length];
    const fragments: string[] = [];
    const sizes: number[] = [];
    for (let i = 1; i < endpoints.length; i++) {
      fragments.push((endpoints[i - 1] + 1) + "-" + endpoints[i]);
      sizes.push(endpoints[i] - endpoints[i - 1]);
    }
    this.emitList("fragments", fragments);
    this.emitList("sizes", sizes.sort((a, b) => b - a));
  }

  repeats(s: string, minimum: number, maximum: number, limit: number): void {
    if (minimum > maximum) throw new CommandError("invalid range");
    const results: Repeat[] = [];
    for (let width = minimum; width <= maximum; width++) {
      let position = 0;
      while (position + width <= s.length) {
        const unit = s.slice(position, position + width);
        const count = repeatCount(s, position, width);
        if (primitive(unit) && count >= limit) {
          results.push({position, width, count, unit});
          position += count * width;
        } else {
          position++;
        }
      }
    }
    results.sort((a, b) => a.position - b.position || a.width - b.width);
    for (const r of results) this.emit((r.position + 1) + "-" + (r.position + r.width * r.count), r.unit + "x" + r.count);
    if (!results.length) this.emit("none");
  }

  align(a: string, b: string, mode: string, match: number, mismatch: number, gap: number): void {
    const m = a.length;
    const n = b.length;
    const local = mode === "LOCAL";
    const table: number[][] = Array.from({length: m + 1}, () => Array(n + 1).fill(0));
    if (!local) {
      for (let i = 0; i <= m; i++) table[i][0] = i * gap;
      for (let j = 0; j <= n; j++) table[0][j] = j * gap;
    }
    let best = 0;
    let endI = 0;
    let endJ = 0;
    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        const diagonal = table[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? match : mismatch);
        const value = Math.max(diagonal, table[i - 1][j] + gap, table[i][j - 1] + gap);
        table[i][j] = local ? Math.max(0, value) : value;
        if (local && table[i][j] > best) {
          best = table[i][j];
          endI = i;
          endJ = j;
        }
      }
    }
    if (!local) {
      endI = m;
      endJ = n;
      best = table[m][n];
    }
    if (local && best === 0) {
      this.emit("score", 0);
      return;
    }
    let i = endI;
    let j = endJ;
    const rowA: string[] = [];
    const rowB: string[] = [];
    while (local ? table[i][j] !== 0 : i !== 0 || j !== 0) {
      if (i && j && table[i][j] === table[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? match : mismatch)) {
        rowA.push(a[i - 1]);
        rowB.push(b[j - 1]);
        i--;
        j--;
      } else if (i && table[i][j] === table[i - 1][j] + gap) {
        rowA.push(a[i - 1]);
        rowB.push("-");
        i--;
      } else {
        rowA.push("-");
        rowB.push(b[j - 1]);
        j--;
      }
    }
    rowA.reverse();
    rowB.reverse();
    const middle = rowA.map((a, h) => a === "-" || rowB[h] === "-" ? "-" : a === rowB[h] ? "|" : "*").join("");
    this.emit("score", best, "a", (i + 1) + "-" + endI, "b", (j + 1) + "-" + endJ,
      "identity", [...middle].filter(c => c === "|").length + "/" + middle.length, "gaps", [...middle].filter(c => c === "-").length);
    this.emit(rowA.join(""));
    this.emit(middle);
    this.emit(rowB.join(""));
  }

  consensus(sequences: string[]): void {
    const n = sequences[0].length;
    if (sequences.some(s => s.length !== n)) throw new CommandError("length mismatch");
    const profile: Record<string, number[]> = Object.fromEntries([...BASES].map(b => [b, []]));
    let consensus = "";
    let ambiguous = "";
    for (let i = 0; i < n; i++) {
      const table = counts(sequences.map(s => s[i]));
      const largest = Math.max(...table.values());
      const tied = [...BASES].filter(b => table.get(b) === largest).join("");
      for (const b of BASES) profile[b].push(table.get(b) ?? 0);
      consensus += tied[0];
      ambiguous += SYMBOL[tied];
    }
    for (const b of BASES) this.emit(b, ...profile[b]);
    this.emit("consensus", consensus);
    this.emit("iupac", ambiguous);
  }

  primer(s: string): void {
    const n = s.length;
    const amount = gc(s);
    const tm = temperature(s);
    const clamp = gc(s.slice(-5));
    const longestRun = Math.max(...s.match(/(.)\1*/g)!.map(run => run.length));
    let repeated = 0;
    for (let i = 0; i + 1 < n; i++) {
      if (s[i] !== s[i + 1]) repeated = Math.max(repeated, repeatCount(s, i, 2));
    }
    const selfcomp = longestPalindrome(s);
    const items: [string, string | number, boolean][] = [
      ["length", n, n >= 18 && n <= 25],
      ["gc", pct(amount, n), 40 * n <= 100 * amount && 100 * amount <= 60 * n],
      ["tm", fixed(tm, 1), tm >= 520 && tm <= 620],
      ["clamp", clamp, clamp >= 1 && clamp <= 3],
      ["run", longestRun, longestRun <= 4],
      ["repeat", repeated, repeated <= 4],
      ["selfcomp", selfcomp, selfcomp <= 6]
    ];
    const failed: string[] = [];
    for (const [label, value, passed] of items) {
      this.emit(label, value, passed ? "OK" : "FAIL");
      if (!passed) failed.push(label);
    }
    this.emit(failed.length ? "FAIL" : "PASS", ...failed);
  }

  fold(s: string, loop: number): void {
    const n = s.length;
    if (n > 100) throw new CommandError("too long");
    const table: number[][] = Array.from({length: n}, () => Array(n).fill(0));
    const value = (i: number, j: number): number => i > j ? 0 : table[i][j];
    const pair = (i: number, j: number): boolean => ["AT", "TA", "CG", "GC", "GT", "TG"].includes(s[i] + s[j]);
    for (let width = 2; width <= n; width++) {
      for (let i = 0; i + width <= n; i++) {
        const j = i + width - 1;
        let best = value(i, j - 1);
        for (let k = i; k <= j - loop - 1; k++) {
          if (pair(k, j)) best = Math.max(best, value(i, k - 1) + 1 + value(k + 1, j - 1));
        }
        table[i][j] = best;
      }
    }
    const structure = Array(n).fill(".") as string[];
    const pending: number[][] = [[0, n - 1]];
    while (pending.length) {
      const [i, j] = pending.pop()!;
      if (value(i, j) === 0) continue;
      if (value(i, j) === value(i, j - 1)) {
        pending.push([i, j - 1]);
        continue;
      }
      for (let k = i; k <= j - loop - 1; k++) {
        if (pair(k, j) && value(i, k - 1) + 1 + value(k + 1, j - 1) === value(i, j)) {
          structure[k] = "(";
          structure[j] = ")";
          pending.push([i, k - 1], [k + 1, j - 1]);
          break;
        }
      }
    }
    this.emit(structure.join(""));
    this.emit("pairs", table[0][n - 1]);
  }

  assemble(name: string, minimum: number, sequences: string[]): void {
    const unique = [...new Set(sequences)];
    let fragments = unique.filter(s => !unique.some(t => t !== s && t.includes(s)));
    while (fragments.length >= 2) {
      let best = -1;
      let chosenI = 0;
      let chosenJ = 1;
      for (let i = 0; i < fragments.length; i++) {
        for (let j = 0; j < fragments.length; j++) {
          if (i === j) continue;
          const x = fragments[i];
          const y = fragments[j];
          let overlap = 0;
          for (let o = Math.min(x.length, y.length) - 1; o >= 1; o--) {
            if (x.slice(-o) === y.slice(0, o)) {
              overlap = o;
              break;
            }
          }
          if (overlap > best) {
            best = overlap;
            chosenI = i;
            chosenJ = j;
          }
        }
      }
      if (best < minimum) break;
      const merged = fragments[chosenI] + fragments[chosenJ].slice(best);
      fragments = fragments.flatMap((s, i) => i === chosenI ? [merged] : i === chosenJ || merged.includes(s) ? [] : [s]);
    }
    const longest = fragments.reduce((best, s) => s.length > best.length ? s : best);
    const registration = this.store(name, longest);
    this.emit("contigs", fragments.length);
    for (const s of fragments) this.emit(s.length, s);
    this.emit(registration);
  }

  command(cmd: string, a: string[]): void {
    if (cmd === "SEQ") {
      this.emit(this.store(a[0], a[1]));
      return;
    }
    if (cmd === "UNPACK") {
      const codes: number[] = [];
      const length = Number(a[1]);
      for (let i = 0; i < a[2].length; i += 2) {
        const v = Number.parseInt(a[2].slice(i, i + 2), 16);
        codes.push(Math.floor(v / 64), Math.floor(v / 16) % 4, Math.floor(v / 4) % 4, v % 4);
      }
      if (codes.slice(length).some(c => c !== 0)) throw new CommandError("invalid padding");
      this.emit(this.store(a[0], codes.slice(0, length).map(c => BASES[c]).join("")));
      return;
    }
    if (cmd === "JOIN") {
      this.emit(this.store(a[0], a.slice(1).map(name => this.registry.get(name)!).join("")));
      return;
    }
    if (cmd === "ASSEMBLE") {
      this.assemble(a[0], Number(a[1]), a.slice(2).map(name => this.registry.get(name)!));
      return;
    }
    if (cmd === "LIST") {
      for (const name of [...this.registry.keys()].sort()) this.emit(name, this.registry.get(name)!.length, "nt");
      if (!this.registry.size) this.emit("no sequences");
      return;
    }
    const name = a[0];
    const s = this.registry.get(name)!;
    const n = s.length;
    switch (cmd) {
      case "SLICE": {
        const start = Number(a[1]);
        const end = Number(a[2]);
        this.emit(this.store(a[3], start <= end ? s.slice(start - 1, end) : revcomp(s.slice(end - 1, start))));
        break;
      }
      case "MUTATE": {
        const position = Number(a[1]);
        const base = a[2];
        const old = s[position - 1];
        if (old === base) throw new CommandError("no change");
        this.registry.set(name, s.slice(0, position - 1) + base + s.slice(position));
        this.emit(name, old + position + base, transition(old, base) ? "transition" : "transversion");
        break;
      }
      case "DEL":
        this.registry.delete(name);
        this.emit("deleted", name);
        break;
      case "REVCOMP":
        this.emit(revcomp(s));
        break;
      case "COMPLEMENT":
        this.emit([...s].map(b => COMPLEMENT[b]).join(""));
        break;
      case "REVERSE":
        this.emit([...s].reverse().join(""));
        break;
      case "TRANSCRIBE":
        this.emit(s.replaceAll("T", "U"));
        break;
      case "TRANSLATE":
      case "CODONS":
      case "PROTEIN":
        this.translation(cmd, s, Number(a[1]));
        break;
      case "ORFS":
        this.orfs(s, Number(a[1]));
        break;
      case "GC": {
        const table = counts(s);
        this.emit(...[...BASES].map(b => b + "=" + (table.get(b) ?? 0)), "GC=" + pct(gc(s), n) + "%");
        break;
      }
      case "GCWINDOW": {
        const width = Number(a[1]);
        const step = Number(a[2]);
        if (width > n) throw new CommandError("window too large");
        for (let i = 0; i + width <= n; i += step) this.emit((i + 1) + "-" + (i + width), pct(gc(s.slice(i, i + width)), width) + "%");
        break;
      }
      case "SKEW": {
        const values = [0];
        for (const b of s) values.push(values[values.length - 1] + Number(b === "G") - Number(b === "C"));
        for (const [label, extreme] of [["min", Math.min(...values)], ["max", Math.max(...values)]] as [string, number][]) {
          this.emit(label, extreme, "at", ...values.flatMap((v, i) => v === extreme ? [i] : []));
        }
        break;
      }
      case "KMERS": {
        const width = Number(a[1]);
        if (width > n) throw new CommandError("k too large");
        const table = counts(Array.from({length: n - width + 1}, (_, i) => s.slice(i, i + width)));
        this.emit(n - width + 1, "windows", table.size, "distinct");
        for (const word of frequencyOrder(table).slice(0, Number(a[2]))) this.emit(word, table.get(word)!);
        break;
      }
      case "FIND":
        this.emitList("forward", occurrences(s, a[1]));
        this.emitList("reverse", occurrences(s, revcomp(a[1])));
        break;
      case "RESTRICT":
        this.restrict(s, a.slice(1));
        break;
      case "PALINDROMES": {
        const minimum = Number(a[1]);
        const maximum = Number(a[2]);
        if (minimum > maximum) throw new CommandError("invalid range");
        let found = false;
        for (let i = 0; i < n; i++) {
          for (let width = minimum; width <= maximum && i + width <= n; width++) {
            const part = s.slice(i, i + width);
            if (part === revcomp(part)) {
              this.emit(i + 1, width, part);
              found = true;
            }
          }
        }
        if (!found) this.emit("none");
        break;
      }
      case "REPEATS":
        this.repeats(s, Number(a[1]), Number(a[2]), Number(a[3]));
        break;
      case "HAMMING": {
        const other = this.registry.get(a[1])!;
        if (other.length !== n) throw new CommandError("length mismatch");
        let distance = 0;
        let transitions = 0;
        for (let i = 0; i < n; i++) {
          if (s[i] !== other[i]) distance++;
          if (transition(s[i], other[i])) transitions++;
        }
        this.emit("distance", distance, "transitions", transitions, "transversions", distance - transitions);
        break;
      }
      case "ALIGN":
        this.align(s, this.registry.get(a[1])!, a[2], Number(a[3]), Number(a[4]), Number(a[5]));
        break;
      case "CONSENSUS":
        this.consensus(a.map(name => this.registry.get(name)!));
        break;
      case "TM":
        this.emit("Tm", fixed(temperature(s), 1), n < 14 ? "wallace" : "gc");
        break;
      case "MASS": {
        const single = strandMass(s);
        this.emit("ss", fixed(single, 3), "ds", fixed(single + strandMass(revcomp(s)), 3));
        break;
      }
      case "PRIMER":
        this.primer(s);
        break;
      case "FOLD":
        this.fold(s, Number(a[1]));
        break;
      case "PACK": {
        const codes = [...s].map(b => BASES.indexOf(b));
        while (codes.length % 4) codes.push(0);
        let encoded = "";
        for (let i = 0; i < codes.length; i += 4) {
          const v = 64 * codes[i] + 16 * codes[i + 1] + 4 * codes[i + 2] + codes[i + 3];
          encoded += v.toString(16).toUpperCase().padStart(2, "0");
        }
        this.emit(n, encoded);
        break;
      }
    }
  }

  execute(line: string): void {
    const [cmd, ...args] = line.split(" ");
    try {
      this.validate(cmd, args);
      this.command(cmd, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("ERROR", error.message);
    }
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const toolkit = new Toolkit();
for (let i = 1; i <= Number(lines[0]); i++) toolkit.execute(lines[i]);
process.stdout.write(toolkit.output.join("\n") + "\n");
