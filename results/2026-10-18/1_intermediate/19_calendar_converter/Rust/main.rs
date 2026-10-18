use std::io::{self, BufRead};

const CALENDARS: [&str; 12] = [
    "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
    "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED",
];
const WEEKDAYS: [&str; 7] = [
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];
const TZOLKIN: [&str; 20] = [
    "Imix", "Ik", "Akbal", "Kan", "Chicchan", "Cimi", "Manik", "Lamat",
    "Muluc", "Oc", "Chuen", "Eb", "Ben", "Ix", "Men", "Cib", "Caban",
    "Etznab", "Cauac", "Ahau",
];
const HAAB: [&str; 19] = [
    "Pop", "Uo", "Zip", "Zotz", "Tzec", "Xul", "Yaxkin", "Mol", "Chen",
    "Yax", "Zac", "Ceh", "Mac", "Kankin", "Muan", "Pax", "Kayab",
    "Cumku", "Uayeb",
];
const DECADES: [&str; 10] = [
    "Primidi", "Duodi", "Tridi", "Quartidi", "Quintidi",
    "Sextidi", "Septidi", "Octidi", "Nonidi", "Decadi",
];
const FESTIVALS: [&str; 6] = [
    "Vertu", "Genie", "Travail", "Opinion", "Recompenses", "Revolution",
];
const HEBREW_LEAP_NAMES: [&str; 13] = [
    "Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "AdarI",
    "AdarII", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul",
];
const MAX_FIXED: i64 = 3_652_059;

const HOLIDAYS: [(&str, &str, &str, i64); 25] = [
    ("Christmas", "GREGORIAN", "December", 25),
    ("OrthodoxChristmas", "JULIAN", "December", 25),
    ("RoshHashanah", "HEBREW", "Tishri", 1),
    ("YomKippur", "HEBREW", "Tishri", 10),
    ("Sukkot", "HEBREW", "Tishri", 15),
    ("Hanukkah", "HEBREW", "Kislev", 25),
    ("Purim", "HEBREW", "Adar", 14),
    ("Passover", "HEBREW", "Nisan", 15),
    ("Shavuot", "HEBREW", "Sivan", 6),
    ("IslamicNewYear", "ISLAMIC", "Muharram", 1),
    ("Ashura", "ISLAMIC", "Muharram", 10),
    ("Mawlid", "ISLAMIC", "RabiI", 12),
    ("RamadanStart", "ISLAMIC", "Ramadan", 1),
    ("EidAlFitr", "ISLAMIC", "Shawwal", 1),
    ("EidAlAdha", "ISLAMIC", "DhuAlHijjah", 10),
    ("Nowruz", "PERSIAN", "Farvardin", 1),
    ("SizdahBedar", "PERSIAN", "Farvardin", 13),
    ("Yalda", "PERSIAN", "Azar", 30),
    ("Nayrouz", "COPTIC", "Thout", 1),
    ("CopticChristmas", "COPTIC", "Koiak", 29),
    ("Enkutatash", "ETHIOPIC", "Meskerem", 1),
    ("Meskel", "ETHIOPIC", "Meskerem", 17),
    ("Timkat", "ETHIOPIC", "Ter", 11),
    ("RepublicDay", "FRENCH", "Vendemiaire", 1),
    ("RevolutionDay", "FRENCH", "Sansculottides", 6),
];

#[derive(Debug)]
enum Problem {
    Command,
    Date(&'static str),
}
type Result<T> = std::result::Result<T, Problem>;

fn ymd(calendar: &str) -> bool {
    matches!(
        calendar,
        "GREGORIAN" | "JULIAN" | "ISLAMIC" | "HEBREW" |
        "PERSIAN" | "COPTIC" | "ETHIOPIC" | "FRENCH"
    )
}

fn year_calendar(calendar: &str) -> bool {
    ymd(calendar) || calendar == "ISO"
}

fn checked(ok: bool) -> Result<()> {
    if ok { Ok(()) } else { Err(Problem::Command) }
}

fn leap(calendar: &str, year: i64) -> bool {
    match calendar {
        "GREGORIAN" =>
            year.rem_euclid(4) == 0 &&
            (year.rem_euclid(100) != 0 || year.rem_euclid(400) == 0),
        "JULIAN" => year.rem_euclid(4) == 0,
        "ISLAMIC" => matches!(
            year.rem_euclid(30), 2 | 5 | 7 | 10 | 13 | 16 | 18 | 21 | 24 | 26 | 29
        ),
        "HEBREW" => (7 * year + 1).rem_euclid(19) < 7,
        "PERSIAN" => {
            let b = (year - 474).rem_euclid(2820) + 474;
            ((b + 38) * 682).rem_euclid(2816) < 682
        }
        "COPTIC" | "ETHIOPIC" => year.rem_euclid(4) == 3,
        "FRENCH" => {
            year.rem_euclid(4) == 0 &&
            !matches!(year.rem_euclid(400), 100 | 200 | 300) &&
            year.rem_euclid(4000) != 0
        }
        _ => (start_fixed("ISO", year + 1) - start_fixed("ISO", year)) / 7 == 53,
    }
}

fn months_before(year: i64) -> i64 {
    (235 * year - 234).div_euclid(19)
}

struct Molad {
    day: i64,
    parts: i64,
    fixed: i64,
    rules: Vec<&'static str>,
}

fn molad(year: i64) -> Molad {
    let quantity = 5604 + 765433 * months_before(year);
    let (day, parts) = (quantity.div_euclid(25920), quantity.rem_euclid(25920));
    let weekday = (day - 1373427).rem_euclid(7);
    let mut postponed = day;
    let mut rules = Vec::new();
    if parts >= 19440 {
        postponed += 1;
        rules.push("ZAKEN");
    } else if !leap("HEBREW", year) && weekday == 2 && parts >= 9924 {
        postponed += 2;
        rules.push("GATARAD");
    } else if leap("HEBREW", year - 1) && weekday == 1 && parts >= 16789 {
        postponed += 1;
        rules.push("BETUTAKPAT");
    }
    if matches!((postponed - 1373427).rem_euclid(7), 0 | 3 | 5) {
        postponed += 1;
        rules.push("ADU");
    }
    Molad { day, parts, fixed: postponed - 1373427, rules }
}

fn start_fixed(calendar: &str, year: i64) -> i64 {
    let previous = year - 1;
    match calendar {
        "GREGORIAN" => {
            365 * previous + previous.div_euclid(4) - previous.div_euclid(100) +
            previous.div_euclid(400) + 1
        }
        "JULIAN" => 365 * previous + previous.div_euclid(4) - 1,
        "ISLAMIC" => 227015 + 354 * previous + (3 + 11 * year).div_euclid(30),
        "HEBREW" => molad(year).fixed,
        "PERSIAN" => {
            let a = year - 474;
            let b = a.rem_euclid(2820) + 474;
            226896 + 1029983 * a.div_euclid(2820) + 365 * (b - 1) +
                (682 * b - 110).div_euclid(2816)
        }
        "COPTIC" => 103605 + 365 * previous + year.div_euclid(4),
        "ETHIOPIC" => 2796 + 365 * previous + year.div_euclid(4),
        "FRENCH" => {
            654415 + 365 * previous + previous.div_euclid(4) -
                previous.div_euclid(100) + previous.div_euclid(400) -
                previous.div_euclid(4000)
        }
        _ => {
            let january_four = start_fixed("GREGORIAN", year) + 3;
            january_four - (january_four - 1).rem_euclid(7)
        }
    }
}

fn year_type(year: i64) -> &'static str {
    match start_fixed("HEBREW", year + 1) - start_fixed("HEBREW", year) {
        353 | 383 => "DEFICIENT",
        354 | 384 => "REGULAR",
        _ => "COMPLETE",
    }
}

fn month_names(calendar: &str, year: i64) -> Vec<&'static str> {
    let names = match calendar {
        "GREGORIAN" | "JULIAN" =>
            "January February March April May June July August September October November December",
        "ISLAMIC" =>
            "Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah",
        "HEBREW" =>
            "Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul",
        "PERSIAN" =>
            "Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand",
        "COPTIC" =>
            "Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie",
        "ETHIOPIC" =>
            "Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume",
        _ =>
            "Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides",
    };
    if calendar == "HEBREW" && leap(calendar, year) {
        HEBREW_LEAP_NAMES.to_vec()
    } else {
        names.split(' ').collect()
    }
}

fn month_lengths(calendar: &str, year: i64) -> Vec<i64> {
    let extra = i64::from(leap(calendar, year));
    match calendar {
        "GREGORIAN" | "JULIAN" =>
            vec![31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
        "ISLAMIC" => {
            let mut days = vec![30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra];
            days.shrink_to_fit();
            days
        }
        "PERSIAN" => {
            let mut days = vec![31; 6];
            days.extend(vec![30; 5]);
            days.push(29 + extra);
            days
        }
        "COPTIC" | "ETHIOPIC" | "FRENCH" => {
            let mut days = vec![30; 12];
            days.push(5 + extra);
            days
        }
        _ => {
            let heshvan = if year_type(year) == "COMPLETE" { 30 } else { 29 };
            let kislev = if year_type(year) == "DEFICIENT" { 29 } else { 30 };
            if extra == 1 {
                vec![30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
            } else {
                vec![30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29]
            }
        }
    }
}

fn fixed_date(calendar: &str, year: i64, month: i64, day: i64) -> i64 {
    if calendar == "ISO" {
        return start_fixed(calendar, year) + 7 * (month - 1) + day - 1;
    }
    let days = month_lengths(calendar, year);
    start_fixed(calendar, year) + days[..(month as usize - 1)].iter().sum::<i64>() + day - 1
}

fn year_of(calendar: &str, fixed: i64) -> i64 {
    if fixed < start_fixed(calendar, 1) {
        return 0;
    }
    let mut low = 1;
    let mut high = 100000;
    while low + 1 < high {
        let middle = (low + high) / 2;
        if start_fixed(calendar, middle) <= fixed {
            low = middle;
        } else {
            high = middle;
        }
    }
    low
}

fn parts_of(calendar: &str, fixed: i64) -> Option<(i64, i64, i64)> {
    let year = year_of(calendar, fixed);
    if year == 0 {
        return None;
    }
    let mut offset = fixed - start_fixed(calendar, year);
    if calendar == "ISO" {
        return Some((year, offset / 7 + 1, offset % 7 + 1));
    }
    for (month, length) in month_lengths(calendar, year).iter().enumerate() {
        if offset < *length {
            return Some((year, month as i64 + 1, offset + 1));
        }
        offset -= length;
    }
    unreachable!("inconsistent calendar year length");
}

fn format_date(calendar: &str, fixed: i64) -> String {
    if !(1..=MAX_FIXED).contains(&fixed) {
        return "OUT OF RANGE".into();
    }
    if year_calendar(calendar) {
        let Some((year, month, day)) = parts_of(calendar, fixed) else {
            return "OUT OF RANGE".into();
        };
        if calendar == "ISO" {
            return format!("{year:04}-W{month:02}-{day}");
        }
        return format!("{year:04}-{month:02}-{day:02}");
    }
    if calendar == "JD" {
        return (fixed + 1721425).to_string();
    }
    if calendar == "FIXED" {
        return fixed.to_string();
    }
    let count = fixed + 1137142;
    let long_count = [
        count.div_euclid(144000),
        count.div_euclid(7200).rem_euclid(20),
        count.div_euclid(360).rem_euclid(20),
        count.div_euclid(20).rem_euclid(18),
        count.rem_euclid(20),
    ];
    let tz_number = (count + 3).rem_euclid(13) + 1;
    let tz_name = TZOLKIN[((count + 19).rem_euclid(20)) as usize];
    let haab = (count + 348).rem_euclid(365);
    format!(
        "{} {} {} {} {}",
        long_count.iter().map(i64::to_string).collect::<Vec<_>>().join("."),
        tz_number, tz_name, haab.rem_euclid(20), HAAB[(haab / 20) as usize]
    )
}

fn decimal_digits(text: &str, low: usize, high: usize) -> bool {
    (low..=high).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit())
}

fn parse_date(calendar: &str, text: &str) -> Result<i64> {
    let fixed;
    if ymd(calendar) {
        let fields: Vec<&str> = text.split('-').collect();
        if fields.len() != 3 || !decimal_digits(fields[0], 1, 5) ||
            !decimal_digits(fields[1], 1, 2) || !decimal_digits(fields[2], 1, 2) {
            return Err(Problem::Date("FORMAT"));
        }
        let year = fields[0].parse::<i64>().unwrap();
        let month = fields[1].parse::<i64>().unwrap();
        let day = fields[2].parse::<i64>().unwrap();
        if year == 0 { return Err(Problem::Date("YEAR")); }
        let days = month_lengths(calendar, year);
        if month < 1 || month > days.len() as i64 {
            return Err(Problem::Date("MONTH"));
        }
        if day < 1 || day > days[month as usize - 1] {
            return Err(Problem::Date("DAY"));
        }
        fixed = fixed_date(calendar, year, month, day);
    } else if calendar == "ISO" {
        let fields: Vec<&str> = text.split('-').collect();
        if fields.len() != 3 || !decimal_digits(fields[0], 1, 5) ||
            !fields[1].starts_with('W') || !decimal_digits(&fields[1][1..], 1, 2) ||
            !decimal_digits(fields[2], 1, 1) {
            return Err(Problem::Date("FORMAT"));
        }
        let year = fields[0].parse::<i64>().unwrap();
        let week = fields[1][1..].parse::<i64>().unwrap();
        let day = fields[2].parse::<i64>().unwrap();
        if year == 0 { return Err(Problem::Date("YEAR")); }
        let weeks = (start_fixed(calendar, year + 1) - start_fixed(calendar, year)) / 7;
        if week < 1 || week > weeks { return Err(Problem::Date("WEEK")); }
        if !(1..=7).contains(&day) { return Err(Problem::Date("DAY")); }
        fixed = fixed_date(calendar, year, week, day);
    } else if calendar == "MAYAN" {
        let fields: Vec<&str> = text.split('.').collect();
        if fields.len() != 5 || fields.iter().any(|s| !decimal_digits(s, 1, 2)) {
            return Err(Problem::Date("FORMAT"));
        }
        let parts: Vec<i64> = fields.iter().map(|s| s.parse().unwrap()).collect();
        let (b, k, t, u, n) = (parts[0], parts[1], parts[2], parts[3], parts[4]);
        if k > 19 || t > 19 || u > 17 || n > 19 {
            return Err(Problem::Date("FIELD"));
        }
        fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142;
    } else {
        let digits = text.strip_prefix('-').unwrap_or(text);
        if !decimal_digits(digits, 1, 8) {
            return Err(Problem::Date("FORMAT"));
        }
        fixed = text.parse::<i64>().unwrap() - if calendar == "JD" { 1721425 } else { 0 };
    }
    if !(1..=MAX_FIXED).contains(&fixed) {
        return Err(Problem::Date("RANGE"));
    }
    Ok(fixed)
}

fn month_index(calendar: &str, year: i64) -> i64 {
    if calendar == "HEBREW" {
        months_before(year)
    } else {
        (if matches!(calendar, "COPTIC" | "ETHIOPIC" | "FRENCH") { 13 } else { 12 })
            * (year - 1)
    }
}

fn shift_date(calendar: &str, fixed: i64, years: i64, months: i64) -> Option<i64> {
    let (year, mut month, day) = parts_of(calendar, fixed)?;
    let target_year = year + years;
    if calendar == "ISO" {
        if !(1..=99999).contains(&target_year) {
            return None;
        }
        let weeks = (start_fixed(calendar, target_year + 1) -
                     start_fixed(calendar, target_year)) / 7;
        return Some(fixed_date(calendar, target_year, month.min(weeks), day));
    }
    if calendar == "HEBREW" {
        let old_names = month_names(calendar, year);
        let mut old_name = old_names[month as usize - 1];
        let new_names = month_names(calendar, target_year);
        if !new_names.contains(&old_name) {
            old_name = if old_name == "Adar" { "AdarII" } else { "Adar" };
        }
        month = new_names.iter().position(|name| *name == old_name)? as i64 + 1;
    }
    let absolute = month_index(calendar, target_year) + month - 1 + months;
    let final_year;
    if calendar == "HEBREW" {
        let mut candidate = (19 * absolute + 234).div_euclid(235);
        while month_index(calendar, candidate) > absolute {
            candidate -= 1;
        }
        while month_index(calendar, candidate + 1) <= absolute {
            candidate += 1;
        }
        final_year = candidate;
    } else {
        let count = month_names(calendar, target_year).len() as i64;
        final_year = absolute.div_euclid(count) + 1;
    }
    if !(1..=99999).contains(&final_year) {
        return None;
    }
    let final_month = absolute - month_index(calendar, final_year) + 1;
    let final_day = day.min(month_lengths(calendar, final_year)[final_month as usize - 1]);
    Some(fixed_date(calendar, final_year, final_month, final_day))
}

fn month_bounds(calendar: &str, year: i64, month: i64) -> Result<(i64, i64)> {
    let lengths = month_lengths(calendar, year);
    if month < 1 || month > lengths.len() as i64 {
        return Err(Problem::Date("MONTH"));
    }
    let first = fixed_date(calendar, year, month, 1);
    Ok((first, first + lengths[month as usize - 1] - 1))
}

fn new_years(calendar: &str, first: i64, last: i64) -> Vec<String> {
    let mut year = year_of(calendar, first).max(1);
    while start_fixed(calendar, year) < first {
        year += 1;
    }
    let mut entries = Vec::new();
    while start_fixed(calendar, year) <= last {
        entries.push(format!("{}:{}", year, format_date("GREGORIAN", start_fixed(calendar, year))));
        year += 1;
    }
    entries
}

struct Easter {
    epact: i64,
    letters: String,
    moon: i64,
    sunday: i64,
}

fn easter(year: i64, calendar: &str) -> Easter {
    let golden = year.rem_euclid(19);
    let mut epact = if calendar == "GREGORIAN" {
        let century = year / 100 + 1;
        (14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25).rem_euclid(30)
    } else {
        (14 + 11 * golden).rem_euclid(30)
    };
    if calendar == "GREGORIAN" && (epact == 0 || (epact == 1 && golden > 10)) {
        epact += 1;
    }
    let moon = fixed_date(calendar, year, 4, 19) - epact;
    let sunday = moon + 7 - moon.rem_euclid(7);
    let index = (-start_fixed(calendar, year)).rem_euclid(7);
    let alphabet = b"ABCDEFG";
    let mut letters = (alphabet[index as usize] as char).to_string();
    if leap(calendar, year) {
        letters.push(alphabet[(index - 1).rem_euclid(7) as usize] as char);
    }
    Easter { epact, letters, moon, sunday }
}

fn holiday_lines(year: i64) -> Vec<String> {
    let first = start_fixed("GREGORIAN", year);
    let last = start_fixed("GREGORIAN", year + 1) - 1;
    let west = easter(year, "GREGORIAN").sunday;
    let east = easter(year, "JULIAN").sunday;
    let movable = [
        ("AshWednesday", -46), ("GoodFriday", -2), ("Easter", 0),
        ("Ascension", 39), ("Pentecost", 49),
    ];
    let mut entries: Vec<(i64, usize, &str, &str)> = Vec::new();
    for (order, (name, offset)) in movable.into_iter().enumerate() {
        entries.push((west + offset, order, name, "GREGORIAN"));
    }
    entries.push((east, 5, "OrthodoxEaster", "JULIAN"));
    for (index, (name, calendar, month_name, day)) in HOLIDAYS.iter().enumerate() {
        let mut candidate_year = year_of(calendar, first).max(1);
        while start_fixed(calendar, candidate_year) <= last {
            let name_in_year = if *calendar == "HEBREW" && *month_name == "Adar" &&
                                  leap(calendar, candidate_year) {
                "AdarII"
            } else {
                month_name
            };
            let names = month_names(calendar, candidate_year);
            let month = names.iter().position(|s| *s == name_in_year).unwrap() as i64 + 1;
            if *day <= month_lengths(calendar, candidate_year)[month as usize - 1] {
                let fixed = fixed_date(calendar, candidate_year, month, *day);
                if first <= fixed && fixed <= last {
                    entries.push((fixed, index + 6, name, calendar));
                }
            }
            candidate_year += 1;
        }
    }
    entries.sort();
    entries.into_iter().map(|(day, _, name, calendar)| {
        format!(
            "{} {} {} {} {}",
            format_date("GREGORIAN", day), WEEKDAYS[day.rem_euclid(7) as usize],
            name, calendar, format_date(calendar, day)
        )
    }).collect()
}

fn valid_year(text: &str) -> bool {
    decimal_digits(text, 1, 5) && text.parse::<i64>().unwrap() >= 1
}

fn arity(command: &str) -> Option<usize> {
    match command {
        "CONVERT" | "DIFF" | "COUNT" | "ADD" => Some(4),
        "MONTHCAL" | "SPAN" => Some(3),
        "NTH" => Some(5),
        "ROUND" => Some(6),
        "PASSOVER" | "HOLIDAYS" | "MOLAD" => Some(1),
        "ALL" | "VALID" | "WEEKDAY" | "INFO" | "LEAP" | "MONTHS" |
        "NEWYEAR" | "EASTER" | "COMPUTUS" => Some(2),
        _ => None,
    }
}

fn validate_arguments(command: &str, args: &[&str]) -> Result<()> {
    if matches!(command, "EASTER" | "COMPUTUS") {
        return checked(valid_year(args[0]) && matches!(args[1], "GREGORIAN" | "JULIAN"));
    }
    if matches!(command, "PASSOVER" | "HOLIDAYS" | "MOLAD") {
        return checked(valid_year(args[0]));
    }
    let calendar = args[0];
    let valid_calendar = if matches!(command, "INFO" | "MONTHS" | "MONTHCAL" | "NTH" | "SPAN") {
        ymd(calendar)
    } else if matches!(command, "LEAP" | "NEWYEAR") {
        year_calendar(calendar)
    } else {
        CALENDARS.contains(&calendar)
    };
    checked(valid_calendar)?;
    match command {
        "CONVERT" => checked(args[2] == "TO" && CALENDARS.contains(&args[3])),
        "DIFF" => checked(CALENDARS.contains(&args[2])),
        "LEAP" | "MONTHS" | "MONTHCAL" | "NTH" | "NEWYEAR" => {
            checked(valid_year(args[1]))?;
            if matches!(command, "MONTHCAL" | "NTH") {
                checked(decimal_digits(args[2], 1, 2))?;
            }
            if command == "NTH" {
                checked(matches!(args[3], "1" | "2" | "3" | "4" | "5" | "LAST"))?;
                checked(WEEKDAYS.contains(&args[4]))?;
            }
            Ok(())
        }
        "COUNT" => checked(WEEKDAYS.contains(&args[3])),
        "ADD" => {
            let digits = args[2].strip_prefix('-').unwrap_or(args[2]);
            checked(decimal_digits(digits, 1, 7))?;
            checked(matches!(args[3], "DAYS" | "WEEKS" | "MONTHS" | "YEARS"))?;
            if args[3] == "MONTHS" {
                checked(ymd(calendar))?;
            }
            if args[3] == "YEARS" {
                checked(year_calendar(calendar))?;
            }
            Ok(())
        }
        "ROUND" => {
            checked(decimal_digits(args[2], 1, 2))?;
            let number: i64 = args[2].parse().unwrap();
            checked((1..=13).contains(&number) && TZOLKIN.contains(&args[3]))?;
            checked(decimal_digits(args[4], 1, 2))?;
            checked(HAAB.contains(&args[5]))?;
            let day: i64 = args[4].parse().unwrap();
            checked(day <= if args[5] == "Uayeb" { 4 } else { 19 })
        }
        _ => Ok(()),
    }
}

fn calendar_lines(calendar: &str, year: i64, month: i64) -> Result<Vec<String>> {
    let (first, last) = month_bounds(calendar, year, month)?;
    if !(1..=MAX_FIXED).contains(&first) || !(1..=MAX_FIXED).contains(&last) {
        return Ok(vec!["OUT OF RANGE".to_string()]);
    }
    let title = format!(
        "{} {} ({} to {})",
        month_names(calendar, year)[month as usize - 1],
        year, format_date("GREGORIAN", first), format_date("GREGORIAN", last)
    );
    let mut lines = vec![title, "Mo Tu We Th Fr Sa Su".to_string()];
    let mut cursor = first - (first - 1).rem_euclid(7);
    while cursor <= last {
        let fields: Vec<String> = (cursor..cursor + 7).map(|day| {
            if first <= day && day <= last {
                format!("{:>2}", day - first + 1)
            } else {
                "  ".into()
            }
        }).collect();
        lines.push(fields.join(" ").trim_end().to_string());
        cursor += 7;
    }
    Ok(lines)
}

fn span_text(calendar: &str, first: i64, last: i64) -> String {
    let negative = first > last;
    let (first, last) = if negative { (last, first) } else { (first, last) };
    let start_year = parts_of(calendar, first).unwrap().0;
    let end_year = parts_of(calendar, last).unwrap().0;
    let mut low = 0;
    let mut high = end_year - start_year + 2;
    while low + 1 < high {
        let middle = (low + high) / 2;
        if shift_date(calendar, first, middle, 0).is_some_and(|day| day <= last) {
            low = middle;
        } else {
            high = middle;
        }
    }
    let years = low;
    low = 0;
    high = 32;
    while low + 1 < high {
        let middle = (low + high) / 2;
        if shift_date(calendar, first, years, middle).is_some_and(|day| day <= last) {
            low = middle;
        } else {
            high = middle;
        }
    }
    let months = low;
    let days = last - shift_date(calendar, first, years, months).unwrap();
    format!("{}{}y {}m {}d", if negative { "-" } else { "" }, years, months, days)
}

fn round_date(calendar: &str, fixed: i64, number: i64, tz_name: &str,
              day: i64, month: &str) -> String {
    let target_tz = TZOLKIN.iter().position(|name| *name == tz_name).unwrap() as i64;
    let target_haab = HAAB.iter().position(|name| *name == month).unwrap() as i64 * 20 + day;
    let mut candidate = fixed;
    loop {
        let count = candidate + 1137142;
        if (count + 3).rem_euclid(13) + 1 == number &&
           (count + 19).rem_euclid(20) == target_tz {
            break;
        }
        candidate += 1;
    }
    while candidate <= fixed + 18979 {
        if (candidate + 1137142 + 348).rem_euclid(365) == target_haab {
            return format_date(calendar, candidate);
        }
        candidate += 260;
    }
    "NONE".to_string()
}

fn execute(command: &str, args: &[&str]) -> Result<Vec<String>> {
    validate_arguments(command, args)?;
    if matches!(command, "EASTER" | "COMPUTUS") {
        let year: i64 = args[0].parse().unwrap();
        if year > 9999 {
            return Ok(vec!["OUT OF RANGE".into()]);
        }
        let kind = args[1];
        let Easter { epact, letters, moon, sunday } = easter(year, kind);
        if command == "EASTER" {
            return Ok(vec![format_date("GREGORIAN", sunday)]);
        }
        return Ok(vec![format!(
            "golden={} epact={} letters={} moon={} easter={}",
            year.rem_euclid(19) + 1, epact, letters,
            format_date(kind, moon), format_date(kind, sunday)
        )]);
    }
    if matches!(command, "PASSOVER" | "HOLIDAYS" | "MOLAD") {
        let year: i64 = args[0].parse().unwrap();
        if command == "MOLAD" {
            let entry = molad(year);
            if !(1..=MAX_FIXED).contains(&entry.fixed) {
                return Ok(vec!["OUT OF RANGE".into()]);
            }
            let applied = if entry.rules.is_empty() {
                "NONE".into()
            } else {
                entry.rules.join("+")
            };
            return Ok(vec![format!(
                "{} {}h {}p {} {} {}",
                WEEKDAYS[(entry.day - 1373427).rem_euclid(7) as usize],
                entry.parts / 1080, entry.parts % 1080, applied,
                WEEKDAYS[entry.fixed.rem_euclid(7) as usize],
                format_date("GREGORIAN", entry.fixed)
            )]);
        }
        if year > 9999 {
            return Ok(vec!["OUT OF RANGE".into()]);
        }
        if command == "HOLIDAYS" {
            return Ok(holiday_lines(year));
        }
        let hebrew_year = year + 3760;
        let month = month_names("HEBREW", hebrew_year)
            .iter().position(|name| *name == "Nisan").unwrap() as i64 + 1;
        let fixed = fixed_date("HEBREW", hebrew_year, month, 15);
        return Ok(vec![format!(
            "{} {}", format_date("GREGORIAN", fixed),
            WEEKDAYS[fixed.rem_euclid(7) as usize]
        )]);
    }

    let calendar = args[0];
    if matches!(command, "LEAP" | "MONTHS" | "MONTHCAL" | "NTH" | "NEWYEAR") {
        let year: i64 = args[1].parse().unwrap();
        if command == "LEAP" {
            let mut result = format!(
                "{} {}", if leap(calendar, year) { "YES" } else { "NO" },
                start_fixed(calendar, year + 1) - start_fixed(calendar, year)
            );
            if calendar == "HEBREW" {
                result.push(' ');
                result.push_str(year_type(year));
            }
            return Ok(vec![result]);
        }
        if command == "MONTHS" {
            let names = month_names(calendar, year);
            let lengths = month_lengths(calendar, year);
            return Ok(vec![names.iter().zip(lengths.iter())
                .map(|(name, days)| format!("{name}={days}"))
                .collect::<Vec<_>>().join(" ")]);
        }
        if command == "NEWYEAR" {
            if year > 9999 {
                return Ok(vec!["OUT OF RANGE".into()]);
            }
            let first = start_fixed("GREGORIAN", year);
            let last = start_fixed("GREGORIAN", year + 1) - 1;
            let entries = new_years(calendar, first, last);
            return Ok(vec![if entries.is_empty() { "NONE".into() } else { entries.join(" ") }]);
        }
        let month: i64 = args[2].parse().unwrap();
        if command == "MONTHCAL" {
            return calendar_lines(calendar, year, month);
        }
        let (first, last) = month_bounds(calendar, year, month)?;
        let weekday = WEEKDAYS.iter().position(|name| *name == args[4]).unwrap() as i64;
        let fixed = if args[3] == "LAST" {
            last - (last - weekday).rem_euclid(7)
        } else {
            first + (weekday - first).rem_euclid(7) +
                7 * (args[3].parse::<i64>().unwrap() - 1)
        };
        return Ok(vec![if fixed > last {
            "NONE".to_string()
        } else {
            format_date(calendar, fixed)
        }]);
    }

    if command == "VALID" {
        return Ok(vec![match parse_date(calendar, args[1]) {
            Ok(day) => format!("YES {}", format_date(calendar, day)),
            Err(Problem::Date(reason)) => format!("NO {reason}"),
            Err(Problem::Command) => unreachable!(),
        }]);
    }
    let first = parse_date(calendar, args[1])?;
    match command {
        "DIFF" => {
            let last = parse_date(args[2], args[3])?;
            Ok(vec![(last - first).to_string()])
        }
        "COUNT" | "SPAN" => {
            let last = parse_date(calendar, args[2])?;
            if command == "SPAN" {
                return Ok(vec![span_text(calendar, first, last)]);
            }
            let (low, high) = if first <= last { (first, last) } else { (last, first) };
            let weekday = WEEKDAYS.iter().position(|name| *name == args[3]).unwrap() as i64;
            let occurrence = low + (weekday - low).rem_euclid(7);
            Ok(vec![if occurrence > high {
                "0".to_string()
            } else {
                ((high - occurrence) / 7 + 1).to_string()
            }])
        }
        "CONVERT" => Ok(vec![format_date(args[3], first)]),
        "WEEKDAY" => Ok(vec![WEEKDAYS[first.rem_euclid(7) as usize].into()]),
        "ALL" => {
            let mut rows = Vec::new();
            for target in CALENDARS {
                let mut text = format_date(target, first);
                if ymd(target) && text != "OUT OF RANGE" {
                    let (year, month, _) = parts_of(target, first).unwrap();
                    text.push(' ');
                    text.push_str(month_names(target, year)[month as usize - 1]);
                }
                rows.push(format!("{target} {text}"));
            }
            Ok(rows)
        }
        "INFO" => {
            let (year, month, day) = parts_of(calendar, first).unwrap();
            let weekday = if calendar == "FRENCH" {
                if month <= 12 {
                    DECADES[(day - 1).rem_euclid(10) as usize]
                } else {
                    FESTIVALS[(day - 1) as usize]
                }
            } else {
                WEEKDAYS[first.rem_euclid(7) as usize]
            };
            let ordinal = first - start_fixed(calendar, year) + 1;
            let length = start_fixed(calendar, year + 1) - start_fixed(calendar, year);
            Ok(vec![format!(
                "{} {} {} {} day={}/{}",
                weekday, day, month_names(calendar, year)[month as usize - 1],
                year, ordinal, length
            )])
        }
        "ROUND" => {
            let number = args[2].parse::<i64>().unwrap();
            let day = args[4].parse::<i64>().unwrap();
            Ok(vec![round_date(calendar, first, number, args[3], day, args[5])])
        }
        "ADD" => {
            let amount = args[2].parse::<i64>().unwrap();
            let result = match args[3] {
                "DAYS" => Some(first + amount),
                "WEEKS" => Some(first + amount * 7),
                "YEARS" => shift_date(calendar, first, amount, 0),
                _ => shift_date(calendar, first, 0, amount),
            };
            Ok(vec![result.map(|day| format_date(calendar, day))
                .unwrap_or_else(|| "OUT OF RANGE".into())])
        }
        _ => unreachable!(),
    }
}

fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut output: Vec<String> = Vec::new();
    for _ in 0..count {
        let line = lines.next().unwrap().unwrap();
        let words: Vec<&str> = line.split(' ').collect();
        let command = words[0];
        let arguments = &words[1..];
        if arity(command) != Some(arguments.len()) {
            output.push("INVALID COMMAND".into());
            continue;
        }
        match execute(command, arguments) {
            Ok(rows) => output.extend(rows),
            Err(Problem::Command) => output.push("INVALID COMMAND".into()),
            Err(Problem::Date(reason)) => output.push(
                if reason == "RANGE" { "OUT OF RANGE" } else { "INVALID DATE" }.into()
            ),
        }
    }
    println!("{}", output.join("\n"));
}
