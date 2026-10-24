import { readFileSync } from "node:fs";

type Style = "APA" | "IEEE" | "CHICAGO" | "MLA";
type EntryType = "article" | "book" | "inproceedings" | "incollection" | "techreport" | "phdthesis" | "misc";
type TemplateType = Exclude<EntryType, "incollection">;
type CitationKind = "cite" | "citep" | "citet" | "citeauthor" | "citeyear";
type SortKey = readonly [string, string, string, string];
type TemplateNode =
  | { readonly kind: "literal"; readonly text: string }
  | { readonly kind: "value"; readonly name: string }
  | { readonly kind: "optional"; readonly children: readonly TemplateNode[] };
interface Citation {
  readonly start: number;
  readonly length: number;
  readonly kind: CitationKind;
  readonly keys: readonly string[];
}
interface AuthorPair {
  readonly a: string;
  readonly b: string;
  count: number;
}
class BibError extends Error {}

const requiredFields: ReadonlyMap<EntryType, readonly string[]> = new Map<EntryType, readonly string[]>([
  ["article", ["author", "title", "journal", "year"]],
  ["book", ["author", "title", "publisher", "year"]],
  ["inproceedings", ["author", "title", "booktitle", "year"]],
  ["incollection", ["author", "title", "booktitle", "publisher", "year"]],
  ["techreport", ["author", "title", "institution", "year"]],
  ["phdthesis", ["author", "title", "school", "year"]],
  ["misc", ["author", "title", "year"]],
]);
const fieldOrder = "author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note".split(" ");
const knownFields = new Set(fieldOrder);
const smallWords = new Set("a an and as at but by for from in into nor of on or over per so the to up via with yet".split(" "));
const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const monthAbbreviations: ReadonlyMap<string, string> = new Map(monthNames.map((month, i) => [month,
  ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."][i],
]));
const styles: ReadonlySet<string> = new Set(["APA", "IEEE", "CHICAGO", "MLA"]);
const commandArity = { FORMAT: -1, BIBLIOGRAPHY: 1, CITE: 2, KEYGEN: 0,
  CHECK: 0, SEARCH: 2, EXPORT: 1, STATS: 0 } as const;
type CommandName = keyof typeof commandArity;
type Command =
  | { readonly kind: "FORMAT"; readonly style: Style; readonly keys: readonly string[] }
  | { readonly kind: "BIBLIOGRAPHY"; readonly style: Style }
  | { readonly kind: "CITE"; readonly style: Style; readonly text: string }
  | { readonly kind: "SEARCH"; readonly field: string; readonly query: string }
  | { readonly kind: "EXPORT"; readonly key: string }
  | { readonly kind: "KEYGEN" | "CHECK" | "STATS" };

const isEntryType = (value: string): value is EntryType => requiredFields.has(value as EntryType);
const isStyle = (value: string): value is Style => styles.has(value);
const isCommandName = (value: string): value is CommandName => Object.hasOwn(commandArity, value);
const compare = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const plain = (text: string): string => text.replace(/[{}]/g, "");
const letters = (text: string): string => text.replace(/[^A-Za-z]/g, "").toLowerCase();
const isLetter = (char: string | undefined): char is string => char !== undefined && /^[A-Za-z]$/.test(char);

function parseCommand(line: string): Command {
  const firstSpace = line.indexOf(" ");
  const name = firstSpace < 0 ? line : line.slice(0, firstSpace);
  if (!isCommandName(name)) throw new BibError(`unknown command '${name}'`);
  let parts: string[];
  if (name === "CITE" || name === "SEARCH") {
    const secondSpace = firstSpace < 0 ? -1 : line.indexOf(" ", firstSpace + 1);
    parts = firstSpace < 0 ? [line] : secondSpace < 0 ? [name, line.slice(firstSpace + 1)]
      : [name, line.slice(firstSpace + 1, secondSpace), line.slice(secondSpace + 1)];
  } else parts = line.split(" ");
  const args = parts.slice(1);
  if (name === "FORMAT" ? args.length < 2 : args.length !== commandArity[name]) {
    throw new BibError("wrong number of arguments");
  }
  if (name === "FORMAT" || name === "BIBLIOGRAPHY" || name === "CITE") {
    const style = args[0];
    if (!isStyle(style)) throw new BibError(`unknown style '${style}'`);
    if (name === "FORMAT") return { kind: name, style, keys: args.slice(1) };
    if (name === "BIBLIOGRAPHY") return { kind: name, style };
    return { kind: name, style, text: args[1] };
  }
  if (name === "SEARCH") return { kind: name, field: args[0], query: args[1] };
  if (name === "EXPORT") return { kind: name, key: args[0] };
  return { kind: name };
}

function compareTuple(a: readonly string[], b: readonly string[]): number {
  for (let i = 0; i < a.length; i++) {
    const order = compare(a[i], b[i]);
    if (order !== 0) return order;
  }
  return 0;
}

function splitAtDepthZero(text: string, separator: string): string[] {
  const parts: string[] = [];
  let depth = 0, start = 0, i = 0;
  while (i < text.length) {
    if (depth === 0 && text.startsWith(separator, i)) {
      parts.push(text.slice(start, i));
      i += separator.length;
      start = i;
    } else {
      if (text[i] === "{") depth++;
      if (text[i] === "}") depth--;
      i++;
    }
  }
  parts.push(text.slice(start));
  return parts;
}

function accentAt(text: string, i: number): { char: string; length: number } | null {
  if (text[i] !== "\\") return null;
  if (text[i + 1] === "&") return { char: "&", length: 2 };
  const symbol = text[i + 1];
  if ("'\"`^~=.".includes(symbol) && isLetter(text[i + 2])) {
    return { char: text[i + 2], length: 3 };
  }
  if ("'\"`^~=.cuvH".includes(symbol) && text[i + 2] === "{" &&
      isLetter(text[i + 3]) && text[i + 4] === "}") {
    return { char: text[i + 3], length: 5 };
  }
  return null;
}

function normalize(text: string): string {
  let result = "";
  for (let i = 0; i < text.length;) {
    const enclosed = text[i] === "{" ? accentAt(text, i + 1) : null;
    if (enclosed && text[i + 1 + enclosed.length] === "}") {
      result += enclosed.char;
      i += enclosed.length + 2;
      continue;
    }
    const accent = accentAt(text, i);
    if (accent) {
      result += accent.char;
      i += accent.length;
    } else {
      result += text[i++];
    }
  }
  return result.replace(/~/g, " ").replace(/ +/g, " ").trim();
}

function evaluateExpression(expression: string, macros: ReadonlyMap<string, string>): string {
  let depth = 0;
  for (const char of expression) {
    if (char === "{") depth++;
    if (char === "}") depth--;
    if (depth < 0) throw new BibError("unbalanced braces");
  }
  if (depth !== 0) throw new BibError("unbalanced braces");
  return expression.split(" # ").map(term => {
    if (term[0] === "{" || term[0] === '"') return term.slice(1, -1);
    if (/^[0-9]+$/.test(term)) return term;
    const value = macros.get(term);
    if (value === undefined) throw new BibError(`unknown macro '${term}'`);
    return value;
  }).join("");
}

class Person {
  readonly first: string;
  readonly von: string;
  readonly last: string;
  readonly jr: string;

  constructor(text: string) {
    const parts = splitAtDepthZero(text, ",").map(part => part.trim());
    const words = splitAtDepthZero(parts[0], " ");
    const lower = words.flatMap((word, i) =>
      i < words.length - 1 && /^[a-z]/.test(word) ? [i] : []);
    this.first = "";
    this.von = "";
    this.jr = "";
    if (parts.length === 1) {
      const start = lower.length ? lower[0] : words.length - 1;
      const end = lower.length ? lower.at(-1)! + 1 : words.length - 1;
      this.first = words.slice(0, start).join(" ");
      this.von = words.slice(start, end).join(" ");
      this.last = words.slice(end).join(" ");
    } else {
      const end = lower.length ? lower.at(-1)! + 1 : 0;
      this.von = words.slice(0, end).join(" ");
      this.last = words.slice(end).join(" ");
      this.first = parts.at(-1)!;
      if (parts.length === 3) this.jr = parts[1];
    }
  }

  surname(): string {
    return plain(this.von ? `${this.von} ${this.last}` : this.last);
  }

  initials(): string {
    const given = plain(this.first);
    if (!given) return "";
    return given.split(" ").map(word => word.split("-").map(piece =>
      piece.match(/[A-Za-z]/)![0].toUpperCase() + ".").join("-")).join(" ");
  }

  format(inverted: boolean, initials: boolean): string {
    const given = initials ? this.initials() : plain(this.first);
    let result = this.surname();
    if (this.first) result = inverted ? `${result}, ${given}` : `${given} ${result}`;
    if (this.jr) result += `, ${plain(this.jr)}`;
    return result;
  }
}

class NameList {
  readonly names: readonly Person[];
  readonly etAl: boolean;
  readonly signature: string;

  constructor(text: string) {
    const parts = splitAtDepthZero(text, " and ");
    this.etAl = parts.at(-1) === "others";
    this.names = (this.etAl ? parts.slice(0, -1) : parts).map(name => new Person(name));
    this.signature = JSON.stringify([
      this.names.map(name => [name.first, name.von, name.last, name.jr]), this.etAl,
    ]);
  }

  singular(): boolean {
    return this.names.length === 1 && !this.etAl;
  }
}

class Entry {
  readonly fields: ReadonlyMap<string, string>;
  readonly author: NameList | null;
  readonly editor: NameList | null;
  readonly primary: NameList;
  readonly sortTitle: string;
  readonly sortKey: SortKey;
  yearSuffix = "";

  constructor(readonly key: string, readonly type: EntryType, fields: ReadonlyMap<string, string>) {
    this.fields = new Map(fields);
    this.author = fields.has("author") ? new NameList(fields.get("author")!) : null;
    this.editor = fields.has("editor") ? new NameList(fields.get("editor")!) : null;
    this.primary = this.author ?? this.editor!;
    this.sortTitle = this.value("title").toLowerCase().replace(/^(a |an |the )/, "");
    this.sortKey = [plain(this.primary.names[0].last).toLowerCase(), this.value("year"), this.sortTitle, key];
  }

  value(name: string): string {
    return plain(this.fields.get(name) ?? "");
  }

  yearLabel(style: Style): string {
    return this.value("year") + (style === "APA" || style === "CHICAGO" ? this.yearSuffix : "");
  }

  unknownFields(): string[] {
    return [...this.fields.keys()].filter(field => !knownFields.has(field)).sort(compare);
  }
}

class Database {
  readonly entries: readonly Entry[];
  readonly byKey: ReadonlyMap<string, Entry>;
  readonly bibliography: readonly Entry[];

  constructor(lines: readonly string[], output: string[]) {
    const entries: Entry[] = [];
    const byKey = new Map<string, Entry>();
    this.entries = entries;
    this.byKey = byKey;
    const macros = new Map(monthNames.map(month => [month.slice(0, 3).toLowerCase(), month]));
    let errorCount = 0;
    const report = (line: number, name: string, reason: string): void => {
      output.push(`ERROR line ${line}: ${name}: ${reason}`);
      errorCount++;
    };
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line || line.startsWith("%")) continue;
      if (line.startsWith("@string{")) {
        const [, name, expression] = line.match(/^@string\{([a-z][a-z0-9]*) = (.*)\}$/)!;
        try {
          const value = evaluateExpression(expression, macros);
          if (macros.has(name)) throw new BibError("duplicate macro");
          macros.set(name, value);
        } catch (error) {
          if (!(error instanceof BibError)) throw error;
          report(i + 1, name, error.message);
        }
        continue;
      }
      const [, type, key] = line.match(/^@([a-z]+)\{([^,]+),$/)!;
      const fields = new Map<string, string>();
      let failed = false;
      const fail = (reason: string): void => {
        report(i + 1, key, reason);
        failed = true;
      };
      if (!isEntryType(type)) fail(`unknown type '${type}'`);
      else if (this.byKey.has(key)) fail("duplicate key");
      while (lines[++i] !== "}") {
        if (failed) continue;
        const [, name, raw] = lines[i].match(/^  ([a-z]+) = (.*)$/)!;
        try {
          const value = evaluateExpression(raw.endsWith(",") ? raw.slice(0, -1) : raw, macros);
          if (fields.has(name)) throw new BibError(`duplicate field '${name}'`);
          fields.set(name, normalize(value));
        } catch (error) {
          if (!(error instanceof BibError)) throw error;
          fail(error.message);
        }
      }
      if (failed || !isEntryType(type)) continue;
      for (const field of requiredFields.get(type)!) {
        if (!fields.has(field) && !(type === "book" && field === "author" && fields.has("editor"))) {
          fail(`missing field '${field}'`);
          break;
        }
      }
      if (!failed) {
        const entry = new Entry(key, type, fields);
        entries.push(entry);
        byKey.set(key, entry);
      }
    }
    output.push(`LOADED entries=${this.entries.length} macros=${macros.size - 12} errors=${errorCount}`);
    const groups = new Map<string, Entry[]>();
    for (const entry of this.entries) {
      const groupKey = JSON.stringify([entry.primary.signature, entry.fields.get("year")]);
      const group = groups.get(groupKey) ?? [];
      group.push(entry);
      groups.set(groupKey, group);
    }
    for (const group of groups.values()) {
      if (group.length < 2) continue;
      group.sort((a, b) => compareTuple([a.sortTitle, a.key], [b.sortTitle, b.key]));
      group.forEach((entry, i) => { entry.yearSuffix = String.fromCharCode(97 + i); });
    }
    this.bibliography = [...this.entries].sort((a, b) => compareTuple(a.sortKey, b.sortKey));
  }
}

function listNames(names: readonly string[], conjunction: string, useListB = false): string {
  if (names.length === 1) return names[0];
  if (useListB && names.length === 2) return names.join(` ${conjunction} `);
  return `${names.slice(0, -1).join(", ")}, ${conjunction} ${names.at(-1)}`;
}

function authorValue(entry: Entry, style: Style, repeated: boolean): string {
  const { names, etAl } = entry.primary;
  let result = "---";
  if (!repeated) {
    if (style === "APA") {
      const formatted = names.map(name => name.format(true, true));
      result = etAl ? formatted.join(", ") + ", et al." : names.length <= 20
        ? listNames(formatted, "&") : formatted.slice(0, 19).join(", ") + ", . . . " + formatted.at(-1);
    } else if (style === "IEEE") {
      const formatted = names.map(name => name.format(false, true));
      result = etAl || names.length >= 7 ? formatted[0] + " et al." : listNames(formatted, "and", true);
    } else {
      const formatted = names.map((name, i) => name.format(i === 0, false));
      if (style === "CHICAGO" && (etAl || names.length >= 11)) result = formatted.slice(0, 7).join(", ") + ", et al.";
      else if (style === "MLA" && (etAl || names.length >= 3)) result = formatted[0] + ", et al.";
      else result = listNames(formatted, "and");
    }
  }
  if (!entry.author) {
    const suffixes = { APA: [" (Ed.)", " (Eds.)"], IEEE: [", Ed.", ", Eds."],
      CHICAGO: [", ed.", ", eds."], MLA: [", editor", ", editors"] };
    result += suffixes[style][entry.primary.singular() ? 0 : 1];
  }
  return result;
}

function editorValue(list: NameList | null, style: Style): string {
  if (!list) return "";
  const names = list.names.map(name => name.format(false, style === "APA" || style === "IEEE"));
  return list.etAl ? names[0] + " et al." : listNames(names, style === "APA" ? "&" : "and", true);
}

function convertLetters(text: string, transform: (char: string, index: number, depth: number) => string): string {
  let depth = 0, result = "";
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === "{") depth++;
    if (char === "}") depth--;
    result += isLetter(char) ? transform(char, i, depth) : char;
  }
  return result;
}

function titleValue(title: string, style: Style): string {
  if (style === "IEEE") return plain(title);
  if (style === "APA") {
    return plain(convertLetters(title, (char, i, depth) => depth ? char :
      i === 0 || title.slice(Math.max(0, i - 2), i) === ": " ? char.toUpperCase() : char.toLowerCase()));
  }
  const words = splitAtDepthZero(title, " ");
  return plain(words.map((word, i) => {
    if (word.startsWith("{")) return word;
    if (i > 0 && i < words.length - 1 && !words[i - 1].endsWith(":") && smallWords.has(letters(word))) {
      return convertLetters(word, (char, _index, depth) => depth ? char : char.toLowerCase());
    }
    let first = true;
    return convertLetters(word, (char, _index, depth) => {
      const result = first && depth === 0 ? char.toUpperCase() : char;
      first = false;
      return result;
    });
  }).join(" "));
}

function ordinal(value: string): string {
  const number = Number(value);
  const lastTwo = number % 100;
  const suffix = lastTwo >= 11 && lastTwo <= 13 ? "th" : number % 10 === 1 ? "st"
    : number % 10 === 2 ? "nd" : number % 10 === 3 ? "rd" : "th";
  return value + suffix;
}

function placeholderValues(entry: Entry, style: Style, repeated: boolean): ReadonlyMap<string, string> {
  const values = new Map([...entry.fields].map(([field, value]) => [field, plain(value)]));
  values.set("author", authorValue(entry, style, repeated));
  values.set("editor", editorValue(entry.editor, style));
  values.set("eds", entry.editor ? entry.editor.singular() ? "Ed." : "Eds." : "");
  values.set("title", titleValue(entry.fields.get("title")!, style));
  values.set("year", entry.yearLabel(style));
  const pages = entry.value("pages").replace(/--/g, "-");
  values.set("pages", pages);
  values.set("pp", entry.fields.has("pages") ? (pages.includes("-") ? "pp. " : "p. ") + pages : "");
  const edition = entry.value("edition");
  values.set("edition", entry.fields.has("edition") ? (/^[0-9]+$/.test(edition) ? ordinal(edition) : edition) + " ed." : "");
  const month = entry.value("month");
  values.set("mon", monthAbbreviations.get(month) ?? month);
  return values;
}

function parseTemplate(source: string): readonly TemplateNode[] {
  let position = 0;
  function sequence(): TemplateNode[] {
    const nodes: TemplateNode[] = [];
    while (position < source.length && source[position] !== ">") {
      if (source[position] === "<") {
        position++;
        nodes.push({ kind: "optional", children: sequence() });
        position++;
      } else if (source[position] === "{") {
        const end = source.indexOf("}", position);
        nodes.push({ kind: "value", name: source.slice(position + 1, end) });
        position = end + 1;
      } else {
        const start = position++;
        while (position < source.length && !"<{>".includes(source[position])) position++;
        nodes.push({ kind: "literal", text: source.slice(start, position) });
      }
    }
    return nodes;
  }
  return sequence();
}

function renderTemplate(nodes: readonly TemplateNode[], values: ReadonlyMap<string, string>): string {
  let result = "";
  function visit(sequence: readonly TemplateNode[]): void {
    for (const node of sequence) {
      if (node.kind === "value") result += values.get(node.name) ?? "";
      else if (node.kind === "optional") {
        if (node.children.every(child => child.kind !== "value" || (values.get(child.name) ?? "") !== "")) visit(node.children);
      } else {
        for (const char of node.text) {
          if (char !== "." || !/[.?!]$/.test(result)) result += char;
        }
      }
    }
  }
  visit(nodes);
  return result;
}

const templateSources: Readonly<Record<Style, Readonly<Record<TemplateType, string>>>> = {
  APA: {
    article: "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
    book: "{author}. ({year}). {title}< ({edition})>. {publisher}.",
    inproceedings: "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
    techreport: "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
    phdthesis: "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
    misc: "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
  },
  IEEE: {
    article: '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
    book: "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
    inproceedings: '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
    techreport: '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
    phdthesis: '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
    misc: '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>',
  },
  CHICAGO: {
    article: '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
    book: "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
    inproceedings: '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
    techreport: "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
    phdthesis: '{author}. {year}. "{title}." PhD diss., {school}.',
    misc: "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
  },
  MLA: {
    article: '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
    book: "{author}. {title}.< {edition},> {publisher}, {year}.",
    inproceedings: '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
    techreport: "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
    phdthesis: "{author}. {title}. {year}. {school}, PhD dissertation.",
    misc: "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
  },
};
const templates: ReadonlyMap<string, ReadonlyMap<string, readonly TemplateNode[]>> = new Map(
  Object.entries(templateSources).map(([style, sources]) =>
    [style, new Map(Object.entries(sources).map(([type, source]) => [type, parseTemplate(source)]))]));

function shortName(entry: Entry, style: Style, parenthetical: boolean): string {
  const names = entry.primary.names.map(name => name.surname());
  if (entry.primary.etAl || names.length >= (style === "CHICAGO" ? 4 : 3)) return names[0] + " et al.";
  return listNames(names, style === "APA" && parenthetical ? "&" : "and", true);
}

class Formatter {
  private readonly citationRecord: string[] = [];
  private readonly cited = new Set<string>();

  constructor(private readonly database: Database, private readonly output: string[]) {}

  private ieeeOrder(): string[] {
    return [...this.citationRecord, ...[...this.database.byKey.keys()].filter(key => !this.cited.has(key)).sort(compare)];
  }

  private ieeeNumbers(): ReadonlyMap<string, number> {
    return new Map(this.ieeeOrder().map((key, i) => [key, i + 1]));
  }

  private reference(entry: Entry, style: Style, numbers: ReadonlyMap<string, number>, repeated = false): string {
    const type = entry.type === "incollection" ? "inproceedings" : entry.type;
    const reference = renderTemplate(templates.get(style)!.get(type)!, placeholderValues(entry, style, repeated));
    return (style === "IEEE" ? `[${numbers.get(entry.key)}] ` : "") + reference;
  }

  private citation(kind: CitationKind, entries: readonly Entry[], style: Style, numbers: ReadonlyMap<string, number>): string {
    const parenthetical = kind === "cite" || kind === "citep";
    const name = (entry: Entry): string => shortName(entry, style, parenthetical);
    if (kind === "citeauthor") return entries.map(name).join("; ");
    if (kind === "citeyear") return entries.map(entry => entry.yearLabel(style)).join(", ");
    if (style === "MLA") {
      const result = entries.map(name).join("; ");
      return parenthetical ? `(${result})` : result;
    }
    if (style === "IEEE") {
      if (!parenthetical) return entries.map(entry => `${name(entry)} [${numbers.get(entry.key)}]`).join("; ");
      const sorted = entries.map(entry => numbers.get(entry.key)!).sort((a, b) => a - b);
      const pieces: string[] = [];
      for (let i = 0; i < sorted.length;) {
        let end = i + 1;
        while (end < sorted.length && sorted[end] === sorted[end - 1] + 1) end++;
        if (end - i >= 3) pieces.push(`[${sorted[i]}]-[${sorted[end - 1]}]`);
        else for (let j = i; j < end; j++) pieces.push(`[${sorted[j]}]`);
        i = end;
      }
      return pieces.join(", ");
    }
    const ordered = parenthetical ? [...entries].sort((a, b) => compareTuple(a.sortKey, b.sortKey)) : entries;
    const groups: { name: string; years: string[] }[] = [];
    for (const entry of ordered) {
      const currentName = name(entry);
      if (!groups.length || groups.at(-1)!.name !== currentName) groups.push({ name: currentName, years: [] });
      groups.at(-1)!.years.push(entry.yearLabel(style));
    }
    const result = groups.map(group => parenthetical
      ? group.name + (style === "APA" ? ", " : " ") + group.years.join(", ")
      : `${group.name} (${group.years.join(", ")})`).join("; ");
    return parenthetical ? `(${result})` : result;
  }

  private cite(style: Style, text: string): void {
    const citations: Citation[] = [...text.matchAll(/\\(citeauthor|citeyear|citep|citet|cite)\{([^}]+)\}/g)].map(match => ({
      start: match.index, length: match[0].length, kind: match[1] as CitationKind, keys: [...new Set(match[2].split(","))],
    }));
    for (const citation of citations) {
      for (const key of citation.keys) {
        if (!this.database.byKey.has(key)) {
          this.output.push(`ERROR unknown key '${key}'`);
          return;
        }
      }
    }
    for (const citation of citations) {
      for (const key of citation.keys) {
        if (!this.cited.has(key)) {
          this.cited.add(key);
          this.citationRecord.push(key);
        }
      }
    }
    const numbers = this.ieeeNumbers();
    let result = "", position = 0;
    for (const citation of citations) {
      result += text.slice(position, citation.start);
      result += this.citation(citation.kind, citation.keys.map(key => this.database.byKey.get(key)!), style, numbers);
      position = citation.start + citation.length;
    }
    this.output.push(result + text.slice(position));
  }

  private keygen(): void {
    const bases = this.database.entries.map(entry => {
      const titleWord = entry.value("title").split(" ").map(letters).find(word => word && !smallWords.has(word)) ?? "";
      return letters(entry.primary.names[0].last) + entry.fields.get("year")!.replace(/[^0-9]/g, "") + titleWord;
    });
    const counts = new Map<string, number>(), used = new Map<string, number>();
    for (const base of bases) counts.set(base, (counts.get(base) ?? 0) + 1);
    this.database.entries.forEach((entry, i) => {
      const base = bases[i];
      const suffix = counts.get(base)! > 1 ? String.fromCharCode(97 + (used.get(base) ?? 0)) : "";
      used.set(base, (used.get(base) ?? 0) + 1);
      this.output.push(`${entry.key} -> ${base}${suffix}`);
    });
  }

  private check(): void {
    let warnings = 0;
    const titles = new Map<string, string>();
    for (const entry of this.database.entries) {
      const warn = (message: string): void => { this.output.push(`WARN ${entry.key}: ${message}`); warnings++; };
      const pages = entry.value("pages"), title = entry.value("title");
      if (pages.includes("-") && !pages.includes("--")) warn("pages use a single hyphen");
      const pageParts = pages.split("-").filter(part => part !== "");
      if (pageParts.length === 2 && pageParts.every(part => /^[0-9]+$/.test(part)) && Number(pageParts[0]) > Number(pageParts[1])) warn("pages are reversed");
      if (!/^[0-9]{4}$/.test(entry.value("year"))) warn("year is not 4 digits");
      if (!/[a-z]/.test(title) && (title.match(/[A-Z]/g)?.length ?? 0) >= 2) warn("title is all caps");
      if (entry.type === "article" && !entry.fields.has("doi")) warn("article has no doi");
      const titleKey = title.toLowerCase();
      if (titles.has(titleKey)) warn(`same title as ${titles.get(titleKey)}`);
      else titles.set(titleKey, entry.key);
      for (const field of entry.unknownFields()) warn(`unknown field '${field}'`);
    }
    this.output.push(`CHECK warnings=${warnings}`);
  }

  private export(key: string): void {
    const entry = this.database.byKey.get(key);
    if (!entry) {
      this.output.push(`ERROR unknown key '${key}'`);
      return;
    }
    this.output.push(`@${entry.type}{${key},`);
    const fields = [...fieldOrder.filter(field => entry.fields.has(field)), ...entry.unknownFields()];
    fields.forEach((field, i) => this.output.push(`  ${field} = {${entry.fields.get(field)}}${i + 1 < fields.length ? "," : ""}`));
    this.output.push("}");
  }

  private stats(): void {
    const types = new Map<EntryType, number>(), years = new Map<string, number>();
    const authors = new Set<string>(), pairs = new Map<string, AuthorPair>();
    for (const entry of this.database.entries) {
      types.set(entry.type, (types.get(entry.type) ?? 0) + 1);
      const year = entry.value("year");
      years.set(year, (years.get(year) ?? 0) + 1);
      if (!entry.author) continue;
      const names = [...new Set(entry.author.names.map(name => name.format(false, false)))].sort(compare);
      for (const name of names) authors.add(name);
      for (let i = 0; i < names.length; i++) {
        for (let j = i + 1; j < names.length; j++) {
          const key = JSON.stringify([names[i], names[j]]);
          if (!pairs.has(key)) pairs.set(key, { a: names[i], b: names[j], count: 0 });
          pairs.get(key)!.count++;
        }
      }
    }
    this.output.push(`ENTRIES ${this.database.entries.length}`);
    for (const type of [...types.keys()].sort(compare)) this.output.push(`TYPE ${type} ${types.get(type)}`);
    for (const year of [...years.keys()].sort(compare)) this.output.push(`YEAR ${year} ${years.get(year)}`);
    this.output.push(`AUTHORS ${authors.size}`);
    const best = [...pairs.values()].sort((a, b) => b.count - a.count || compareTuple([a.a, a.b], [b.a, b.b]))[0];
    this.output.push(best ? `PAIR ${best.a} & ${best.b} ${best.count}` : "PAIR none");
  }

  command(command: Command): void {
    switch (command.kind) {
      case "FORMAT": {
        const numbers = this.ieeeNumbers();
        for (const key of command.keys) {
          const entry = this.database.byKey.get(key);
          this.output.push(entry ? this.reference(entry, command.style, numbers) : `ERROR unknown key '${key}'`);
        }
        break;
      }
      case "BIBLIOGRAPHY": {
        const { style } = command;
        const numbers = this.ieeeNumbers();
        const entries = style === "IEEE" ? this.ieeeOrder().map(key => this.database.byKey.get(key)!) : this.database.bibliography;
        this.output.push(style === "MLA" ? "Works Cited" : "References");
        let previous: string | null = null;
        for (const entry of entries) {
          const repeated = (style === "CHICAGO" || style === "MLA") && previous === entry.primary.signature;
          this.output.push(this.reference(entry, style, numbers, repeated));
          previous = entry.primary.signature;
        }
        break;
      }
      case "CITE": this.cite(command.style, command.text); break;
      case "KEYGEN": this.keygen(); break;
      case "CHECK": this.check(); break;
      case "EXPORT": this.export(command.key); break;
      case "STATS": this.stats(); break;
      case "SEARCH": {
        const query = command.query.toLowerCase();
        const keys = this.database.entries.filter(entry => entry.fields.has(command.field) &&
          entry.value(command.field).toLowerCase().includes(query)).map(entry => entry.key);
        this.output.push(keys.length ? `MATCHES ${keys.length}: ${keys.join(" ")}` : "MATCHES 0");
        break;
      }
    }
  }
}

const lines = readFileSync(0, "utf8").split(/\r?\n/);
const separator = lines.indexOf("%%");
const output: string[] = [];
const formatter = new Formatter(new Database(lines.slice(0, separator), output), output);
const count = Number(lines[separator + 1]);
for (let i = 0; i < count; i++) {
  try {
    formatter.command(parseCommand(lines[separator + i + 2]));
  } catch (error) {
    if (!(error instanceof BibError)) throw error;
    output.push(`ERROR ${error.message}`);
  }
}
process.stdout.write(output.join("\n") + "\n");
