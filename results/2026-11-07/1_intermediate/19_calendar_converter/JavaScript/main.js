import { readFileSync } from "node:fs";


const CALENDARS = [
  "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
  "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED"
];
const YMD = CALENDARS.filter(calendar => !["ISO", "MAYAN", "JD", "FIXED"].includes(calendar));
const YEAR_CALENDARS = [...YMD, "ISO"];
const WEEKDAYS = "Sunday Monday Tuesday Wednesday Thursday Friday Saturday".split(" ");
const TZ = "Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau".split(" ");
const HB = "Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb".split(" ");
const DC = "Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi".split(" ");
const FS = "Vertu Genie Travail Opinion Recompenses Revolution".split(" ");
const MAX_FIXED = 3652059;
const MONTH_NAMES = {
  GREGORIAN: "January February March April May June July August September October November December".split(" "),
  JULIAN: "January February March April May June July August September October November December".split(" "),
  ISLAMIC: "Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah".split(" "),
  HEBREW: "Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul".split(" "),
  PERSIAN: "Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand".split(" "),
  COPTIC: "Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie".split(" "),
  ETHIOPIC: "Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume".split(" "),
  FRENCH: "Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides".split(" ")
};
const HEBREW_LEAP_NAMES = "Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul".split(" ");

class DateError extends Error {}
class CommandError extends Error {}

function requireValid(condition) {
  if (!condition) throw new CommandError();
}

function floorDiv(n, d) {
  return Math.floor(n / d);
}

function mod(n, d) {
  return ((n % d) + d) % d;
}

function pad(value, width) {
  return String(value).padStart(width, "0");
}

function inRange(fixed) {
  return fixed >= 1 && fixed <= MAX_FIXED;
}

function leap(calendar, year) {
  if (calendar === "GREGORIAN") return mod(year, 4) === 0 && (mod(year, 100) !== 0 || mod(year, 400) === 0);
  if (calendar === "JULIAN") return mod(year, 4) === 0;
  if (calendar === "ISLAMIC") return [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29].includes(mod(year, 30));
  if (calendar === "HEBREW") return mod(7 * year + 1, 19) < 7;
  if (calendar === "PERSIAN") {
    const b = mod(year - 474, 2820) + 474;
    return mod((b + 38) * 682, 2816) < 682;
  }
  if (calendar === "COPTIC" || calendar === "ETHIOPIC") return mod(year, 4) === 3;
  if (calendar === "FRENCH") {
    return mod(year, 4) === 0 && ![100, 200, 300].includes(mod(year, 400)) && mod(year, 4000) !== 0;
  }
  return (start("ISO", year + 1) - start("ISO", year)) / 7 === 53;
}

function monthsBefore(year) {
  return floorDiv(235 * year - 234, 19);
}

function molad(year) {
  const quantity = 5604 + 765433 * monthsBefore(year);
  const day = floorDiv(quantity, 25920);
  const parts = mod(quantity, 25920);
  const weekday = mod(day - 1373427, 7);
  const rules = [];
  let postponed = day;
  if (parts >= 19440) {
    postponed += 1;
    rules.push("ZAKEN");
  } else if (!leap("HEBREW", year) && weekday === 2 && parts >= 9924) {
    postponed += 2;
    rules.push("GATARAD");
  } else if (leap("HEBREW", year - 1) && weekday === 1 && parts >= 16789) {
    postponed += 1;
    rules.push("BETUTAKPAT");
  }
  if ([0, 3, 5].includes(mod(postponed - 1373427, 7))) {
    postponed += 1;
    rules.push("ADU");
  }
  return {day, parts, fixed: postponed - 1373427, rules};
}

function start(calendar, year) {
  const previous = year - 1;
  if (calendar === "GREGORIAN") {
    return 365 * previous + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) + 1;
  }
  if (calendar === "JULIAN") return 365 * previous + floorDiv(previous, 4) - 1;
  if (calendar === "ISLAMIC") return 227015 + 354 * previous + floorDiv(3 + 11 * year, 30);
  if (calendar === "HEBREW") return molad(year).fixed;
  if (calendar === "PERSIAN") {
    const a = year - 474;
    const b = mod(a, 2820) + 474;
    return 226896 + 1029983 * floorDiv(a, 2820) + 365 * (b - 1) + floorDiv(682 * b - 110, 2816);
  }
  if (calendar === "COPTIC") return 103605 + 365 * previous + floorDiv(year, 4);
  if (calendar === "ETHIOPIC") return 2796 + 365 * previous + floorDiv(year, 4);
  if (calendar === "FRENCH") {
    return 654415 + 365 * previous + floorDiv(previous, 4) - floorDiv(previous, 100) +
      floorDiv(previous, 400) - floorDiv(previous, 4000);
  }
  const januaryFour = start("GREGORIAN", year) + 3;
  return januaryFour - mod(januaryFour - 1, 7);
}

function yearType(year) {
  const length = start("HEBREW", year + 1) - start("HEBREW", year);
  if (length === 353 || length === 383) return "DEFICIENT";
  if (length === 354 || length === 384) return "REGULAR";
  return "COMPLETE";
}

function names(calendar, year) {
  if (calendar === "HEBREW" && leap(calendar, year)) return HEBREW_LEAP_NAMES;
  return MONTH_NAMES[calendar];
}

function lengths(calendar, year) {
  const extra = leap(calendar, year) ? 1 : 0;
  if (calendar === "GREGORIAN" || calendar === "JULIAN") return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (calendar === "ISLAMIC") return [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra];
  if (calendar === "PERSIAN") return [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra];
  if (["COPTIC", "ETHIOPIC", "FRENCH"].includes(calendar)) return [...Array(12).fill(30), 5 + extra];
  const kind = yearType(year);
  const heshvan = kind === "COMPLETE" ? 30 : 29;
  const kislev = kind === "DEFICIENT" ? 29 : 30;
  if (extra) return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29];
  return [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29];
}

function fixedDate(calendar, year, month, day) {
  if (calendar === "ISO") return start(calendar, year) + 7 * (month - 1) + day - 1;
  const before = lengths(calendar, year).slice(0, month - 1).reduce((sum, days) => sum + days, 0);
  return start(calendar, year) + before + day - 1;
}

function yearOf(calendar, fixed) {
  if (fixed < start(calendar, 1)) return 0;
  let low = 1;
  let high = 100000;
  while (low + 1 < high) {
    const middle = floorDiv(low + high, 2);
    if (start(calendar, middle) <= fixed) low = middle;
    else high = middle;
  }
  return low;
}

function partsOf(calendar, fixed) {
  const year = yearOf(calendar, fixed);
  if (year === 0) return null;
  let offset = fixed - start(calendar, year);
  if (calendar === "ISO") return [year, floorDiv(offset, 7) + 1, mod(offset, 7) + 1];
  for (const [index, days] of lengths(calendar, year).entries()) {
    if (offset < days) return [year, index + 1, offset + 1];
    offset -= days;
  }
  throw new Error("calendar year length");
}

function formatDate(calendar, fixed) {
  if (!inRange(fixed)) return "OUT OF RANGE";
  if (YEAR_CALENDARS.includes(calendar)) {
    const parts = partsOf(calendar, fixed);
    if (parts === null) return "OUT OF RANGE";
    const [year, month, day] = parts;
    if (calendar === "ISO") return pad(year, 4) + "-W" + pad(month, 2) + "-" + day;
    return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2);
  }
  if (calendar === "JD") return String(fixed + 1721425);
  if (calendar === "FIXED") return String(fixed);
  const count = fixed + 1137142;
  const longCount = [
    floorDiv(count, 144000),
    mod(floorDiv(count, 7200), 20),
    mod(floorDiv(count, 360), 20),
    mod(floorDiv(count, 20), 18),
    mod(count, 20)
  ];
  const tzNumber = mod(count + 3, 13) + 1;
  const tzName = TZ[mod(count + 19, 20)];
  const haab = mod(count + 348, 365);
  return longCount.join(".") + " " + tzNumber + " " + tzName + " " + mod(haab, 20) + " " + HB[floorDiv(haab, 20)];
}

function parseDate(calendar, text) {
  let fixed;
  if (YMD.includes(calendar)) {
    if (!/^[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}$/.test(text)) throw new DateError("FORMAT");
    const [year, month, day] = text.split("-").map(Number);
    if (year === 0) throw new DateError("YEAR");
    const days = lengths(calendar, year);
    if (month < 1 || month > days.length) throw new DateError("MONTH");
    if (day < 1 || day > days[month - 1]) throw new DateError("DAY");
    fixed = fixedDate(calendar, year, month, day);
  } else if (calendar === "ISO") {
    if (!/^[0-9]{1,5}-W[0-9]{1,2}-[0-9]$/.test(text)) throw new DateError("FORMAT");
    const [yearText, weekText, dayText] = text.split("-");
    const year = Number(yearText);
    const week = Number(weekText.slice(1));
    const day = Number(dayText);
    if (year === 0) throw new DateError("YEAR");
    const weeks = (start(calendar, year + 1) - start(calendar, year)) / 7;
    if (week < 1 || week > weeks) throw new DateError("WEEK");
    if (day < 1 || day > 7) throw new DateError("DAY");
    fixed = fixedDate(calendar, year, week, day);
  } else if (calendar === "MAYAN") {
    if (!/^[0-9]{1,2}(?:\.[0-9]{1,2}){4}$/.test(text)) throw new DateError("FORMAT");
    const [b, k, t, u, n] = text.split(".").map(Number);
    if (k > 19 || t > 19 || u > 17 || n > 19) throw new DateError("FIELD");
    fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142;
  } else {
    if (!/^-?[0-9]{1,8}$/.test(text)) throw new DateError("FORMAT");
    fixed = Number(text) - (calendar === "JD" ? 1721425 : 0);
  }
  if (!inRange(fixed)) throw new DateError("RANGE");
  return fixed;
}

function monthIndex(calendar, year) {
  if (calendar === "HEBREW") return monthsBefore(year);
  const count = ["COPTIC", "ETHIOPIC", "FRENCH"].includes(calendar) ? 13 : 12;
  return count * (year - 1);
}

function shift(calendar, fixed, years, months) {
  let [year, month, day] = partsOf(calendar, fixed);
  const targetYear = year + years;
  if (calendar === "ISO") {
    if (targetYear < 1 || targetYear > 99999) return null;
    const weeks = (start(calendar, targetYear + 1) - start(calendar, targetYear)) / 7;
    return fixedDate(calendar, targetYear, Math.min(month, weeks), day);
  }
  if (calendar === "HEBREW") {
    let oldName = names(calendar, year)[month - 1];
    const newNames = names(calendar, targetYear);
    if (!newNames.includes(oldName)) oldName = oldName === "Adar" ? "AdarII" : "Adar";
    month = newNames.indexOf(oldName) + 1;
  }
  const absolute = monthIndex(calendar, targetYear) + month - 1 + months;
  let finalYear;
  if (calendar === "HEBREW") {
    finalYear = floorDiv(19 * absolute + 234, 235);
    while (monthIndex(calendar, finalYear) > absolute) finalYear--;
    while (monthIndex(calendar, finalYear + 1) <= absolute) finalYear++;
  } else {
    finalYear = floorDiv(absolute, names(calendar, targetYear).length) + 1;
  }
  if (finalYear < 1 || finalYear > 99999) return null;
  const finalMonth = absolute - monthIndex(calendar, finalYear) + 1;
  const finalDay = Math.min(day, lengths(calendar, finalYear)[finalMonth - 1]);
  return fixedDate(calendar, finalYear, finalMonth, finalDay);
}

function monthBounds(calendar, year, month) {
  const days = lengths(calendar, year);
  if (month < 1 || month > days.length) throw new DateError("MONTH");
  const first = fixedDate(calendar, year, month, 1);
  return [first, first + days[month - 1] - 1];
}

function newYears(calendar, first, last) {
  let year = Math.max(1, yearOf(calendar, first));
  while (start(calendar, year) < first) year++;
  const result = [];
  while (start(calendar, year) <= last) {
    result.push([year, start(calendar, year)]);
    year++;
  }
  return result;
}

function easter(year, calendar) {
  const golden = mod(year, 19);
  let epact;
  if (calendar === "GREGORIAN") {
    const century = floorDiv(year, 100) + 1;
    epact = mod(14 + 11 * golden - floorDiv(3 * century, 4) + floorDiv(5 + 8 * century, 25), 30);
    if (epact === 0 || (epact === 1 && golden > 10)) epact += 1;
  } else {
    epact = mod(14 + 11 * golden, 30);
  }
  const moon = fixedDate(calendar, year, 4, 19) - epact;
  const sunday = moon + 7 - mod(moon, 7);
  const index = mod(-start(calendar, year), 7);
  let letters = "ABCDEFG"[index];
  if (leap(calendar, year)) letters += "ABCDEFG"[mod(index - 1, 7)];
  return {epact, letters, moon, sunday};
}

const HOLIDAYS = [
  ["Christmas", "GREGORIAN", "December", 25],
  ["OrthodoxChristmas", "JULIAN", "December", 25],
  ["RoshHashanah", "HEBREW", "Tishri", 1],
  ["YomKippur", "HEBREW", "Tishri", 10],
  ["Sukkot", "HEBREW", "Tishri", 15],
  ["Hanukkah", "HEBREW", "Kislev", 25],
  ["Purim", "HEBREW", "Adar", 14],
  ["Passover", "HEBREW", "Nisan", 15],
  ["Shavuot", "HEBREW", "Sivan", 6],
  ["IslamicNewYear", "ISLAMIC", "Muharram", 1],
  ["Ashura", "ISLAMIC", "Muharram", 10],
  ["Mawlid", "ISLAMIC", "RabiI", 12],
  ["RamadanStart", "ISLAMIC", "Ramadan", 1],
  ["EidAlFitr", "ISLAMIC", "Shawwal", 1],
  ["EidAlAdha", "ISLAMIC", "DhuAlHijjah", 10],
  ["Nowruz", "PERSIAN", "Farvardin", 1],
  ["SizdahBedar", "PERSIAN", "Farvardin", 13],
  ["Yalda", "PERSIAN", "Azar", 30],
  ["Nayrouz", "COPTIC", "Thout", 1],
  ["CopticChristmas", "COPTIC", "Koiak", 29],
  ["Enkutatash", "ETHIOPIC", "Meskerem", 1],
  ["Meskel", "ETHIOPIC", "Meskerem", 17],
  ["Timkat", "ETHIOPIC", "Ter", 11],
  ["RepublicDay", "FRENCH", "Vendemiaire", 1],
  ["RevolutionDay", "FRENCH", "Sansculottides", 6]
];

function holidayLines(year) {
  const first = start("GREGORIAN", year);
  const last = start("GREGORIAN", year + 1) - 1;
  const gregorianEaster = easter(year, "GREGORIAN").sunday;
  const orthodoxEaster = easter(year, "JULIAN").sunday;
  const movable = [["AshWednesday", -46], ["GoodFriday", -2], ["Easter", 0], ["Ascension", 39], ["Pentecost", 49]];
  const entries = movable.map(([name, offset], order) => ({fixed: gregorianEaster + offset, order, name, calendar: "GREGORIAN"}));
  entries.push({fixed: orthodoxEaster, order: 5, name: "OrthodoxEaster", calendar: "JULIAN"});
  HOLIDAYS.forEach(([name, calendar, monthName, day], index) => {
    for (let candidateYear = Math.max(1, yearOf(calendar, first)); start(calendar, candidateYear) <= last; candidateYear++) {
      let actualName = monthName;
      if (calendar === "HEBREW" && monthName === "Adar" && leap(calendar, candidateYear)) actualName = "AdarII";
      const month = names(calendar, candidateYear).indexOf(actualName) + 1;
      if (day <= lengths(calendar, candidateYear)[month - 1]) {
        const fixed = fixedDate(calendar, candidateYear, month, day);
        if (first <= fixed && fixed <= last) entries.push({fixed, order: index + 6, name, calendar});
      }
    }
  });
  entries.sort((a, b) => a.fixed - b.fixed || a.order - b.order);
  return entries.map(({fixed, name, calendar}) =>
    formatDate("GREGORIAN", fixed) + " " + WEEKDAYS[mod(fixed, 7)] + " " + name + " " + calendar + " " + formatDate(calendar, fixed));
}

const ARITY = new Map([
  ["CONVERT", 4], ["ALL", 2], ["VALID", 2], ["WEEKDAY", 2], ["INFO", 2],
  ["LEAP", 2], ["MONTHS", 2], ["MONTHCAL", 3], ["NTH", 5], ["NEWYEAR", 2],
  ["DIFF", 4], ["COUNT", 4], ["ADD", 4], ["SPAN", 3], ["EASTER", 2],
  ["COMPUTUS", 2], ["PASSOVER", 1], ["HOLIDAYS", 1], ["MOLAD", 1], ["ROUND", 6]
]);

function validYear(text) {
  return /^[0-9]{1,5}$/.test(text) && Number(text) >= 1;
}

function validateArguments(command, args) {
  if (command === "EASTER" || command === "COMPUTUS") {
    requireValid(validYear(args[0]) && ["GREGORIAN", "JULIAN"].includes(args[1]));
    return;
  }
  if (["PASSOVER", "HOLIDAYS", "MOLAD"].includes(command)) {
    requireValid(validYear(args[0]));
    return;
  }
  const calendar = args[0];
  let allowed = CALENDARS;
  if (["INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN"].includes(command)) allowed = YMD;
  else if (command === "LEAP" || command === "NEWYEAR") allowed = YEAR_CALENDARS;
  requireValid(allowed.includes(calendar));
  if (command === "CONVERT") {
    requireValid(args[2] === "TO" && CALENDARS.includes(args[3]));
  } else if (command === "DIFF") {
    requireValid(CALENDARS.includes(args[2]));
  } else if (["LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"].includes(command)) {
    requireValid(validYear(args[1]));
    if (command === "MONTHCAL" || command === "NTH") requireValid(/^[0-9]{1,2}$/.test(args[2]));
    if (command === "NTH") {
      requireValid(["1", "2", "3", "4", "5", "LAST"].includes(args[3]));
      requireValid(WEEKDAYS.includes(args[4]));
    }
  } else if (command === "COUNT") {
    requireValid(WEEKDAYS.includes(args[3]));
  } else if (command === "ADD") {
    requireValid(/^-?[0-9]{1,7}$/.test(args[2]));
    requireValid(["DAYS", "WEEKS", "MONTHS", "YEARS"].includes(args[3]));
    if (args[3] === "MONTHS") requireValid(YMD.includes(calendar));
    if (args[3] === "YEARS") requireValid(YEAR_CALENDARS.includes(calendar));
  } else if (command === "ROUND") {
    requireValid(/^[0-9]{1,2}$/.test(args[2]));
    requireValid(Number(args[2]) >= 1 && Number(args[2]) <= 13 && TZ.includes(args[3]));
    requireValid(/^[0-9]{1,2}$/.test(args[4]));
    requireValid(HB.includes(args[5]));
    requireValid(Number(args[4]) <= (args[5] === "Uayeb" ? 4 : 19));
  }
}

function calendarLines(calendar, year, month) {
  const [first, last] = monthBounds(calendar, year, month);
  if (!inRange(first) || !inRange(last)) return ["OUT OF RANGE"];
  const title = names(calendar, year)[month - 1] + " " + year +
    " (" + formatDate("GREGORIAN", first) + " to " + formatDate("GREGORIAN", last) + ")";
  const result = [title, "Mo Tu We Th Fr Sa Su"];
  for (let cursor = first - mod(first - 1, 7); cursor <= last; cursor += 7) {
    const fields = Array.from({length: 7}, (_, i) => {
      const fixed = cursor + i;
      return first <= fixed && fixed <= last ? String(fixed - first + 1).padStart(2) : "  ";
    });
    result.push(fields.join(" ").trimEnd());
  }
  return result;
}

function spanText(calendar, first, last) {
  const negative = first > last;
  if (negative) [first, last] = [last, first];
  const startYear = partsOf(calendar, first)[0];
  const endYear = partsOf(calendar, last)[0];
  let low = 0;
  let high = endYear - startYear + 2;
  while (low + 1 < high) {
    const middle = floorDiv(low + high, 2);
    const shifted = shift(calendar, first, middle, 0);
    if (shifted !== null && shifted <= last) low = middle;
    else high = middle;
  }
  const years = low;
  low = 0;
  high = 32;
  while (low + 1 < high) {
    const middle = floorDiv(low + high, 2);
    const shifted = shift(calendar, first, years, middle);
    if (shifted !== null && shifted <= last) low = middle;
    else high = middle;
  }
  const months = low;
  const days = last - shift(calendar, first, years, months);
  return (negative ? "-" : "") + years + "y " + months + "m " + days + "d";
}

function roundDate(calendar, fixed, number, tzName, day, month) {
  const targetTz = TZ.indexOf(tzName);
  const targetHaab = HB.indexOf(month) * 20 + day;
  let candidate = fixed;
  while (true) {
    const count = candidate + 1137142;
    if (mod(count + 3, 13) + 1 === number && mod(count + 19, 20) === targetTz) break;
    candidate++;
  }
  while (candidate <= fixed + 18979) {
    if (mod(candidate + 1137142 + 348, 365) === targetHaab) return formatDate(calendar, candidate);
    candidate += 260;
  }
  return "NONE";
}

function execute(command, args) {
  validateArguments(command, args);
  if (command === "EASTER" || command === "COMPUTUS") {
    const year = Number(args[0]);
    if (year > 9999) return ["OUT OF RANGE"];
    const kind = args[1];
    const {epact, letters, moon, sunday} = easter(year, kind);
    if (command === "EASTER") return [formatDate("GREGORIAN", sunday)];
    return ["golden=" + (mod(year, 19) + 1) + " epact=" + epact + " letters=" + letters +
      " moon=" + formatDate(kind, moon) + " easter=" + formatDate(kind, sunday)];
  }
  if (["PASSOVER", "HOLIDAYS", "MOLAD"].includes(command)) {
    const year = Number(args[0]);
    if (command === "MOLAD") {
      const {day, parts, fixed, rules} = molad(year);
      if (!inRange(fixed)) return ["OUT OF RANGE"];
      const applied = rules.length ? rules.join("+") : "NONE";
      return [WEEKDAYS[mod(day - 1373427, 7)] + " " + floorDiv(parts, 1080) + "h " + mod(parts, 1080) + "p " +
        applied + " " + WEEKDAYS[mod(fixed, 7)] + " " + formatDate("GREGORIAN", fixed)];
    }
    if (year > 9999) return ["OUT OF RANGE"];
    if (command === "HOLIDAYS") return holidayLines(year);
    const hebrewYear = year + 3760;
    const month = names("HEBREW", hebrewYear).indexOf("Nisan") + 1;
    const fixed = fixedDate("HEBREW", hebrewYear, month, 15);
    return [formatDate("GREGORIAN", fixed) + " " + WEEKDAYS[mod(fixed, 7)]];
  }
  const calendar = args[0];
  if (["LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"].includes(command)) {
    const year = Number(args[1]);
    if (command === "LEAP") {
      let text = (leap(calendar, year) ? "YES" : "NO") + " " + (start(calendar, year + 1) - start(calendar, year));
      if (calendar === "HEBREW") text += " " + yearType(year);
      return [text];
    }
    if (command === "MONTHS") {
      const days = lengths(calendar, year);
      return [names(calendar, year).map((name, i) => name + "=" + days[i]).join(" ")];
    }
    if (command === "NEWYEAR") {
      if (year > 9999) return ["OUT OF RANGE"];
      const first = start("GREGORIAN", year);
      const last = start("GREGORIAN", year + 1) - 1;
      const entries = newYears(calendar, first, last);
      return [entries.map(([y, f]) => y + ":" + formatDate("GREGORIAN", f)).join(" ") || "NONE"];
    }
    const month = Number(args[2]);
    if (command === "MONTHCAL") return calendarLines(calendar, year, month);
    const [first, last] = monthBounds(calendar, year, month);
    const weekday = WEEKDAYS.indexOf(args[4]);
    let fixed;
    if (args[3] === "LAST") fixed = last - mod(last - weekday, 7);
    else fixed = first + mod(weekday - first, 7) + 7 * (Number(args[3]) - 1);
    return [fixed > last ? "NONE" : formatDate(calendar, fixed)];
  }
  if (command === "VALID") {
    try {
      return ["YES " + formatDate(calendar, parseDate(calendar, args[1]))];
    } catch (error) {
      if (!(error instanceof DateError)) throw error;
      return ["NO " + error.message];
    }
  }
  const first = parseDate(calendar, args[1]);
  if (command === "DIFF") {
    const last = parseDate(args[2], args[3]);
    return [String(last - first)];
  }
  if (command === "COUNT" || command === "SPAN") {
    const last = parseDate(calendar, args[2]);
    if (command === "SPAN") return [spanText(calendar, first, last)];
    const low = Math.min(first, last);
    const high = Math.max(first, last);
    const occurrence = low + mod(WEEKDAYS.indexOf(args[3]) - low, 7);
    return [String(occurrence > high ? 0 : floorDiv(high - occurrence, 7) + 1)];
  }
  if (command === "CONVERT") return [formatDate(args[3], first)];
  if (command === "WEEKDAY") return [WEEKDAYS[mod(first, 7)]];
  if (command === "ALL") {
    return CALENDARS.map(target => {
      let text = formatDate(target, first);
      if (YMD.includes(target) && text !== "OUT OF RANGE") {
        const [year, month] = partsOf(target, first);
        text += " " + names(target, year)[month - 1];
      }
      return target + " " + text;
    });
  }
  if (command === "INFO") {
    const [year, month, day] = partsOf(calendar, first);
    let weekday = WEEKDAYS[mod(first, 7)];
    if (calendar === "FRENCH") weekday = month <= 12 ? DC[mod(day - 1, 10)] : FS[day - 1];
    const ordinal = first - start(calendar, year) + 1;
    const length = start(calendar, year + 1) - start(calendar, year);
    return [weekday + " " + day + " " + names(calendar, year)[month - 1] + " " + year + " day=" + ordinal + "/" + length];
  }
  if (command === "ROUND") {
    return [roundDate(calendar, first, Number(args[2]), args[3], Number(args[4]), args[5])];
  }
  const amount = Number(args[2]);
  const unit = args[3];
  let result;
  if (unit === "DAYS") result = first + amount;
  else if (unit === "WEEKS") result = first + 7 * amount;
  else if (unit === "YEARS") result = shift(calendar, first, amount, 0);
  else result = shift(calendar, first, 0, amount);
  return [result === null ? "OUT OF RANGE" : formatDate(calendar, result)];
}

const lines = readFileSync(0, "utf8").split("\n");
const output = [];
for (let i = 1; i <= Number(lines[0]); i++) {
  const [command, ...args] = lines[i].split(" ");
  if (!ARITY.has(command) || args.length !== ARITY.get(command)) {
    output.push("INVALID COMMAND");
    continue;
  }
  try {
    output.push(...execute(command, args));
  } catch (error) {
    if (error instanceof CommandError) output.push("INVALID COMMAND");
    else if (error instanceof DateError) output.push(error.message === "RANGE" ? "OUT OF RANGE" : "INVALID DATE");
    else throw error;
  }
}
process.stdout.write(output.join("\n") + "\n");
