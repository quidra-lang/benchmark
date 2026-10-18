calendars <- c(
  "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
  "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED"
)
ymd <- setdiff(calendars, c("ISO", "MAYAN", "JD", "FIXED"))
year_calendars <- c(ymd, "ISO")
weekdays <- strsplit("Sunday Monday Tuesday Wednesday Thursday Friday Saturday", " ")[[1]]
tzolkin <- strsplit(
  "Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau",
  " "
)[[1]]
haab <- strsplit(
  "Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb",
  " "
)[[1]]
decades <- strsplit("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi", " ")[[1]]
festival <- strsplit("Vertu Genie Travail Opinion Recompenses Revolution", " ")[[1]]
month_names <- list(
  GREGORIAN = strsplit("January February March April May June July August September October November December", " ")[[1]],
  JULIAN = strsplit("January February March April May June July August September October November December", " ")[[1]],
  ISLAMIC = strsplit("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah", " ")[[1]],
  HEBREW = strsplit("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul", " ")[[1]],
  PERSIAN = strsplit("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand", " ")[[1]],
  COPTIC = strsplit("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie", " ")[[1]],
  ETHIOPIC = strsplit("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume", " ")[[1]],
  FRENCH = strsplit("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides", " ")[[1]]
)
hebrew_leap_names <- strsplit("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul", " ")[[1]]
maximum_fixed <- 3652059

arity <- c(
  CONVERT = 4, ALL = 2, VALID = 2, WEEKDAY = 2, INFO = 2,
  LEAP = 2, MONTHS = 2, MONTHCAL = 3, NTH = 5, NEWYEAR = 2,
  DIFF = 4, COUNT = 4, ADD = 4, SPAN = 3, EASTER = 2,
  COMPUTUS = 2, PASSOVER = 1, HOLIDAYS = 1, MOLAD = 1, ROUND = 6
)

command_error <- function() stop("COMMAND", call. = FALSE)
date_error <- function(reason) stop(reason, call. = FALSE)
require_command <- function(valid) {
  if (!isTRUE(valid)) command_error()
}
supported <- function(fixed) fixed >= 1 && fixed <= maximum_fixed
digits <- function(text, count) grepl(paste0("^[0-9]{1,", count, "}$"), text)
year_valid <- function(text) digits(text, 5) && as.numeric(text) >= 1

leap <- function(calendar, year) {
  if (calendar == "GREGORIAN")
    return(year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0))
  if (calendar == "JULIAN") return(year %% 4 == 0)
  if (calendar == "ISLAMIC")
    return(year %% 30 %in% c(2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29))
  if (calendar == "HEBREW") return((7 * year + 1) %% 19 < 7)
  if (calendar == "PERSIAN") {
    b <- (year - 474) %% 2820 + 474
    return(((b + 38) * 682) %% 2816 < 682)
  }
  if (calendar %in% c("COPTIC", "ETHIOPIC")) return(year %% 4 == 3)
  if (calendar == "FRENCH")
    return(year %% 4 == 0 && !(year %% 400 %in% c(100, 200, 300)) && year %% 4000 != 0)
  (start_fixed("ISO", year + 1) - start_fixed("ISO", year)) / 7 == 53
}

months_before <- function(year) floor((235 * year - 234) / 19)

molad <- function(year) {
  quantity <- 5604 + 765433 * months_before(year)
  day <- floor(quantity / 25920)
  parts <- quantity %% 25920
  weekday <- (day - 1373427) %% 7
  postponed <- day
  rules <- character()
  if (parts >= 19440) {
    postponed <- postponed + 1
    rules <- c(rules, "ZAKEN")
  } else if (!leap("HEBREW", year) && weekday == 2 && parts >= 9924) {
    postponed <- postponed + 2
    rules <- c(rules, "GATARAD")
  } else if (leap("HEBREW", year - 1) && weekday == 1 && parts >= 16789) {
    postponed <- postponed + 1
    rules <- c(rules, "BETUTAKPAT")
  }
  if ((postponed - 1373427) %% 7 %in% c(0, 3, 5)) {
    postponed <- postponed + 1
    rules <- c(rules, "ADU")
  }
  list(day = day, parts = parts, fixed = postponed - 1373427, rules = rules)
}

start_fixed <- function(calendar, year) {
  previous <- year - 1
  if (calendar == "GREGORIAN")
    return(365 * previous + floor(previous / 4) - floor(previous / 100) +
             floor(previous / 400) + 1)
  if (calendar == "JULIAN") return(365 * previous + floor(previous / 4) - 1)
  if (calendar == "ISLAMIC")
    return(227015 + 354 * previous + floor((3 + 11 * year) / 30))
  if (calendar == "HEBREW") return(molad(year)$fixed)
  if (calendar == "PERSIAN") {
    a <- year - 474
    b <- a %% 2820 + 474
    return(226896 + 1029983 * floor(a / 2820) + 365 * (b - 1) +
             floor((682 * b - 110) / 2816))
  }
  if (calendar == "COPTIC") return(103605 + 365 * previous + floor(year / 4))
  if (calendar == "ETHIOPIC") return(2796 + 365 * previous + floor(year / 4))
  if (calendar == "FRENCH")
    return(654415 + 365 * previous + floor(previous / 4) -
             floor(previous / 100) + floor(previous / 400) - floor(previous / 4000))
  january_four <- start_fixed("GREGORIAN", year) + 3
  january_four - (january_four - 1) %% 7
}

year_type <- function(year) {
  length <- start_fixed("HEBREW", year + 1) - start_fixed("HEBREW", year)
  if (length %in% c(353, 383)) return("DEFICIENT")
  if (length %in% c(354, 384)) return("REGULAR")
  "COMPLETE"
}

names_for <- function(calendar, year) {
  if (calendar == "HEBREW" && leap(calendar, year)) return(hebrew_leap_names)
  month_names[[calendar]]
}

month_lengths <- function(calendar, year) {
  extra <- as.integer(leap(calendar, year))
  if (calendar %in% c("GREGORIAN", "JULIAN"))
    return(c(31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
  if (calendar == "ISLAMIC") return(c(rep(c(30, 29), 5), 30, 29 + extra))
  if (calendar == "PERSIAN") return(c(rep(31, 6), rep(30, 5), 29 + extra))
  if (calendar %in% c("COPTIC", "ETHIOPIC", "FRENCH"))
    return(c(rep(30, 12), 5 + extra))
  kind <- year_type(year)
  heshvan <- if (kind == "COMPLETE") 30 else 29
  kislev <- if (kind == "DEFICIENT") 29 else 30
  if (extra == 1)
    return(c(30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29))
  c(30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29)
}

fixed_date <- function(calendar, year, month, day) {
  if (calendar == "ISO") return(start_fixed(calendar, year) + 7 * (month - 1) + day - 1)
  start_fixed(calendar, year) + sum(head(month_lengths(calendar, year), month - 1)) + day - 1
}

year_of <- function(calendar, fixed) {
  if (fixed < start_fixed(calendar, 1)) return(0)
  low <- 1
  high <- 100000
  while (low + 1 < high) {
    middle <- floor((low + high) / 2)
    if (start_fixed(calendar, middle) <= fixed) low <- middle else high <- middle
  }
  low
}

parts_of <- function(calendar, fixed) {
  year <- year_of(calendar, fixed)
  if (year == 0) return(NULL)
  offset <- fixed - start_fixed(calendar, year)
  if (calendar == "ISO")
    return(c(year, floor(offset / 7) + 1, offset %% 7 + 1))
  lengths <- month_lengths(calendar, year)
  for (month in seq_along(lengths)) {
    if (offset < lengths[month]) return(c(year, month, offset + 1))
    offset <- offset - lengths[month]
  }
  stop("Inconsistent calendar year", call. = FALSE)
}

format_date <- function(calendar, fixed) {
  if (!supported(fixed)) return("OUT OF RANGE")
  if (calendar %in% year_calendars) {
    fields <- parts_of(calendar, fixed)
    if (is.null(fields)) return("OUT OF RANGE")
    if (calendar == "ISO")
      return(sprintf("%04d-W%02d-%d", fields[1], fields[2], fields[3]))
    return(sprintf("%04d-%02d-%02d", fields[1], fields[2], fields[3]))
  }
  if (calendar == "JD") return(sprintf("%.0f", fixed + 1721425))
  if (calendar == "FIXED") return(sprintf("%.0f", fixed))
  count <- fixed + 1137142
  digits <- c(
    floor(count / 144000),
    floor(count / 7200) %% 20,
    floor(count / 360) %% 20,
    floor(count / 20) %% 18,
    count %% 20
  )
  tz_number <- (count + 3) %% 13 + 1
  tz_name <- tzolkin[(count + 19) %% 20 + 1]
  haab_count <- (count + 348) %% 365
  paste(
    paste(digits, collapse = "."), tz_number, tz_name,
    haab_count %% 20, haab[floor(haab_count / 20) + 1]
  )
}

parse_date <- function(calendar, text) {
  if (calendar %in% ymd) {
    if (!grepl("^[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}$", text))
      date_error("FORMAT")
    components <- as.numeric(strsplit(text, "-", fixed = TRUE)[[1]])
    year <- components[1]
    month <- components[2]
    day <- components[3]
    if (year == 0) date_error("YEAR")
    lengths <- month_lengths(calendar, year)
    if (month < 1 || month > length(lengths)) date_error("MONTH")
    if (day < 1 || day > lengths[month]) date_error("DAY")
    fixed <- fixed_date(calendar, year, month, day)
  } else if (calendar == "ISO") {
    if (!grepl("^[0-9]{1,5}-W[0-9]{1,2}-[0-9]$", text)) date_error("FORMAT")
    components <- strsplit(text, "-", fixed = TRUE)[[1]]
    year <- as.numeric(components[1])
    week <- as.numeric(substring(components[2], 2))
    day <- as.numeric(components[3])
    if (year == 0) date_error("YEAR")
    weeks <- (start_fixed(calendar, year + 1) - start_fixed(calendar, year)) / 7
    if (week < 1 || week > weeks) date_error("WEEK")
    if (day < 1 || day > 7) date_error("DAY")
    fixed <- fixed_date(calendar, year, week, day)
  } else if (calendar == "MAYAN") {
    if (!grepl("^[0-9]{1,2}(\\.[0-9]{1,2}){4}$", text))
      date_error("FORMAT")
    values <- as.numeric(strsplit(text, ".", fixed = TRUE)[[1]])
    if (values[2] > 19 || values[3] > 19 || values[4] > 17 || values[5] > 19)
      date_error("FIELD")
    fixed <- (((values[1] * 20 + values[2]) * 20 + values[3]) *
                18 + values[4]) * 20 + values[5] - 1137142
  } else {
    if (!grepl("^-?[0-9]{1,8}$", text)) date_error("FORMAT")
    fixed <- as.numeric(text)
    if (calendar == "JD") fixed <- fixed - 1721425
  }
  if (!supported(fixed)) date_error("RANGE")
  fixed
}

month_index <- function(calendar, year) {
  if (calendar == "HEBREW") return(months_before(year))
  count <- if (calendar %in% c("COPTIC", "ETHIOPIC", "FRENCH")) 13 else 12
  count * (year - 1)
}

shift_date <- function(calendar, fixed, years, months) {
  fields <- parts_of(calendar, fixed)
  year <- fields[1]
  month <- fields[2]
  day <- fields[3]
  target_year <- year + years
  if (calendar == "ISO") {
    if (target_year < 1 || target_year > 99999) return(NA_real_)
    weeks <- (start_fixed(calendar, target_year + 1) - start_fixed(calendar, target_year)) / 7
    return(fixed_date(calendar, target_year, min(month, weeks), day))
  }
  if (calendar == "HEBREW") {
    old_name <- names_for(calendar, year)[month]
    new_names <- names_for(calendar, target_year)
    if (!(old_name %in% new_names))
      old_name <- if (old_name == "Adar") "AdarII" else "Adar"
    month <- match(old_name, new_names)
  }
  absolute <- month_index(calendar, target_year) + month - 1 + months
  if (calendar == "HEBREW") {
    final_year <- floor((19 * absolute + 234) / 235)
    while (month_index(calendar, final_year) > absolute)
      final_year <- final_year - 1
    while (month_index(calendar, final_year + 1) <= absolute)
      final_year <- final_year + 1
  } else {
    count <- length(names_for(calendar, target_year))
    final_year <- floor(absolute / count) + 1
  }
  if (final_year < 1 || final_year > 99999) return(NA_real_)
  final_month <- absolute - month_index(calendar, final_year) + 1
  final_day <- min(day, month_lengths(calendar, final_year)[final_month])
  fixed_date(calendar, final_year, final_month, final_day)
}

month_bounds <- function(calendar, year, month) {
  days <- month_lengths(calendar, year)
  if (month < 1 || month > length(days)) date_error("MONTH")
  first <- fixed_date(calendar, year, month, 1)
  c(first, first + days[month] - 1)
}

new_years <- function(calendar, first, last) {
  year <- max(1, year_of(calendar, first))
  while (start_fixed(calendar, year) < first) year <- year + 1
  result <- character()
  while (start_fixed(calendar, year) <= last) {
    result <- c(result, paste0(year, ":", format_date("GREGORIAN", start_fixed(calendar, year))))
    year <- year + 1
  }
  result
}

easter <- function(year, calendar) {
  golden <- year %% 19
  if (calendar == "GREGORIAN") {
    century <- floor(year / 100) + 1
    epact <- (14 + 11 * golden - floor(3 * century / 4) +
                floor((5 + 8 * century) / 25)) %% 30
    if (epact == 0 || (epact == 1 && golden > 10)) epact <- epact + 1
  } else {
    epact <- (14 + 11 * golden) %% 30
  }
  moon <- fixed_date(calendar, year, 4, 19) - epact
  sunday <- moon + 7 - moon %% 7
  index <- (-start_fixed(calendar, year)) %% 7
  letters <- substring("ABCDEFG", index + 1, index + 1)
  if (leap(calendar, year)) {
    another <- (index - 1) %% 7
    letters <- paste0(letters, substring("ABCDEFG", another + 1, another + 1))
  }
  list(epact = epact, letters = letters, moon = moon, sunday = sunday)
}

holidays <- matrix(c(
  "Christmas", "GREGORIAN", "December", "25",
  "OrthodoxChristmas", "JULIAN", "December", "25",
  "RoshHashanah", "HEBREW", "Tishri", "1",
  "YomKippur", "HEBREW", "Tishri", "10",
  "Sukkot", "HEBREW", "Tishri", "15",
  "Hanukkah", "HEBREW", "Kislev", "25",
  "Purim", "HEBREW", "Adar", "14",
  "Passover", "HEBREW", "Nisan", "15",
  "Shavuot", "HEBREW", "Sivan", "6",
  "IslamicNewYear", "ISLAMIC", "Muharram", "1",
  "Ashura", "ISLAMIC", "Muharram", "10",
  "Mawlid", "ISLAMIC", "RabiI", "12",
  "RamadanStart", "ISLAMIC", "Ramadan", "1",
  "EidAlFitr", "ISLAMIC", "Shawwal", "1",
  "EidAlAdha", "ISLAMIC", "DhuAlHijjah", "10",
  "Nowruz", "PERSIAN", "Farvardin", "1",
  "SizdahBedar", "PERSIAN", "Farvardin", "13",
  "Yalda", "PERSIAN", "Azar", "30",
  "Nayrouz", "COPTIC", "Thout", "1",
  "CopticChristmas", "COPTIC", "Koiak", "29",
  "Enkutatash", "ETHIOPIC", "Meskerem", "1",
  "Meskel", "ETHIOPIC", "Meskerem", "17",
  "Timkat", "ETHIOPIC", "Ter", "11",
  "RepublicDay", "FRENCH", "Vendemiaire", "1",
  "RevolutionDay", "FRENCH", "Sansculottides", "6"
), ncol = 4, byrow = TRUE)

holiday_lines <- function(year) {
  first <- start_fixed("GREGORIAN", year)
  last <- start_fixed("GREGORIAN", year + 1) - 1
  western <- easter(year, "GREGORIAN")$sunday
  orthodox <- easter(year, "JULIAN")$sunday
  fixed <- numeric()
  priority <- integer()
  name <- character()
  calendar <- character()
  add <- function(day, order, label, kind) {
    fixed <<- c(fixed, day)
    priority <<- c(priority, order)
    name <<- c(name, label)
    calendar <<- c(calendar, kind)
  }
  movable <- c(AshWednesday = -46, GoodFriday = -2, Easter = 0,
               Ascension = 39, Pentecost = 49)
  for (i in seq_along(movable))
    add(western + movable[i], i - 1, names(movable)[i], "GREGORIAN")
  add(orthodox, 5, "OrthodoxEaster", "JULIAN")
  for (i in seq_len(nrow(holidays))) {
    entry <- holidays[i, ]
    kind <- entry[2]
    candidate <- max(1, year_of(kind, first))
    while (start_fixed(kind, candidate) <= last) {
      months <- names_for(kind, candidate)
      month_name <- entry[3]
      if (kind == "HEBREW" && month_name == "Adar" && leap(kind, candidate))
        month_name <- "AdarII"
      month <- match(month_name, months)
      day <- as.numeric(entry[4])
      if (day <= month_lengths(kind, candidate)[month]) {
        current <- fixed_date(kind, candidate, month, day)
        if (first <= current && current <= last)
          add(current, 5 + i, entry[1], kind)
      }
      candidate <- candidate + 1
    }
  }
  sorted <- order(fixed, priority)
  result <- character()
  for (i in sorted) {
    day <- fixed[i]
    result <- c(result, paste(
      format_date("GREGORIAN", day), weekdays[day %% 7 + 1],
      name[i], calendar[i], format_date(calendar[i], day)
    ))
  }
  result
}

validate_arguments <- function(command, args) {
  if (command %in% c("EASTER", "COMPUTUS")) {
    require_command(year_valid(args[1]) && args[2] %in% c("GREGORIAN", "JULIAN"))
    return(invisible(NULL))
  }
  if (command %in% c("PASSOVER", "HOLIDAYS", "MOLAD")) {
    require_command(year_valid(args[1]))
    return(invisible(NULL))
  }
  calendar <- args[1]
  allowed <- calendars
  if (command %in% c("INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN")) {
    allowed <- ymd
  } else if (command %in% c("LEAP", "NEWYEAR")) {
    allowed <- year_calendars
  }
  require_command(calendar %in% allowed)
  if (command == "CONVERT") {
    require_command(args[3] == "TO" && args[4] %in% calendars)
  } else if (command == "DIFF") {
    require_command(args[3] %in% calendars)
  } else if (command %in% c("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR")) {
    require_command(year_valid(args[2]))
    if (command %in% c("MONTHCAL", "NTH")) require_command(digits(args[3], 2))
    if (command == "NTH") {
      require_command(args[4] %in% c("1", "2", "3", "4", "5", "LAST"))
      require_command(args[5] %in% weekdays)
    }
  } else if (command == "COUNT") {
    require_command(args[4] %in% weekdays)
  } else if (command == "ADD") {
    require_command(grepl("^-?[0-9]{1,7}$", args[3]))
    require_command(args[4] %in% c("DAYS", "WEEKS", "MONTHS", "YEARS"))
    if (args[4] == "MONTHS") require_command(calendar %in% ymd)
    if (args[4] == "YEARS") require_command(calendar %in% year_calendars)
  } else if (command == "ROUND") {
    require_command(digits(args[3], 2))
    require_command(as.numeric(args[3]) >= 1 && as.numeric(args[3]) <= 13)
    require_command(args[4] %in% tzolkin)
    require_command(digits(args[5], 2))
    require_command(args[6] %in% haab)
    maximum_day <- if (args[6] == "Uayeb") 4 else 19
    require_command(as.numeric(args[5]) <= maximum_day)
  }
}

calendar_lines <- function(calendar, year, month) {
  bounds <- month_bounds(calendar, year, month)
  first <- bounds[1]
  last <- bounds[2]
  if (!supported(first) || !supported(last)) return("OUT OF RANGE")
  title <- paste0(
    names_for(calendar, year)[month], " ", year, " (",
    format_date("GREGORIAN", first), " to ", format_date("GREGORIAN", last), ")"
  )
  result <- c(title, "Mo Tu We Th Fr Sa Su")
  cursor <- first - (first - 1) %% 7
  while (cursor <= last) {
    fields <- character()
    for (day in cursor:(cursor + 6)) {
      if (first <= day && day <= last) {
        fields <- c(fields, sprintf("%2d", day - first + 1))
      } else {
        fields <- c(fields, "  ")
      }
    }
    result <- c(result, sub("[[:space:]]+$", "", paste(fields, collapse = " ")))
    cursor <- cursor + 7
  }
  result
}

span_text <- function(calendar, first, last) {
  negative <- first > last
  if (negative) {
    temporary <- first
    first <- last
    last <- temporary
  }
  first_year <- parts_of(calendar, first)[1]
  last_year <- parts_of(calendar, last)[1]
  low <- 0
  high <- last_year - first_year + 2
  while (low + 1 < high) {
    middle <- floor((low + high) / 2)
    shifted <- shift_date(calendar, first, middle, 0)
    if (!is.na(shifted) && shifted <= last) low <- middle else high <- middle
  }
  years <- low
  low <- 0
  high <- 32
  while (low + 1 < high) {
    middle <- floor((low + high) / 2)
    shifted <- shift_date(calendar, first, years, middle)
    if (!is.na(shifted) && shifted <= last) low <- middle else high <- middle
  }
  months <- low
  days <- last - shift_date(calendar, first, years, months)
  paste0(if (negative) "-" else "", years, "y ", months, "m ", days, "d")
}

round_date <- function(calendar, fixed, number, tz_name, day, month) {
  target_tz <- match(tz_name, tzolkin) - 1
  target_haab <- (match(month, haab) - 1) * 20 + day
  candidate <- fixed
  repeat {
    count <- candidate + 1137142
    if ((count + 3) %% 13 + 1 == number && (count + 19) %% 20 == target_tz) break
    candidate <- candidate + 1
  }
  while (candidate <= fixed + 18979) {
    if ((candidate + 1137142 + 348) %% 365 == target_haab)
      return(format_date(calendar, candidate))
    candidate <- candidate + 260
  }
  "NONE"
}

execute <- function(command, args) {
  validate_arguments(command, args)
  if (command %in% c("EASTER", "COMPUTUS")) {
    year <- as.numeric(args[1])
    if (year > 9999) return("OUT OF RANGE")
    kind <- args[2]
    result <- easter(year, kind)
    if (command == "EASTER") return(format_date("GREGORIAN", result$sunday))
    return(paste0(
      "golden=", year %% 19 + 1, " epact=", result$epact, " letters=", result$letters,
      " moon=", format_date(kind, result$moon),
      " easter=", format_date(kind, result$sunday)
    ))
  }
  if (command %in% c("PASSOVER", "HOLIDAYS", "MOLAD")) {
    year <- as.numeric(args[1])
    if (command == "MOLAD") {
      result <- molad(year)
      if (!supported(result$fixed)) return("OUT OF RANGE")
      applied <- if (length(result$rules)) paste(result$rules, collapse = "+") else "NONE"
      return(paste(
        weekdays[(result$day - 1373427) %% 7 + 1],
        paste0(floor(result$parts / 1080), "h"),
        paste0(result$parts %% 1080, "p"),
        applied, weekdays[result$fixed %% 7 + 1],
        format_date("GREGORIAN", result$fixed)
      ))
    }
    if (year > 9999) return("OUT OF RANGE")
    if (command == "HOLIDAYS") return(holiday_lines(year))
    hebrew_year <- year + 3760
    month <- match("Nisan", names_for("HEBREW", hebrew_year))
    day <- fixed_date("HEBREW", hebrew_year, month, 15)
    return(paste(format_date("GREGORIAN", day), weekdays[day %% 7 + 1]))
  }
  calendar <- args[1]
  if (command %in% c("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR")) {
    year <- as.numeric(args[2])
    if (command == "LEAP") {
      result <- paste(
        if (leap(calendar, year)) "YES" else "NO",
        start_fixed(calendar, year + 1) - start_fixed(calendar, year)
      )
      if (calendar == "HEBREW") result <- paste(result, year_type(year))
      return(result)
    }
    if (command == "MONTHS")
      return(paste(
        paste0(names_for(calendar, year), "=", month_lengths(calendar, year)),
        collapse = " "
      ))
    if (command == "NEWYEAR") {
      if (year > 9999) return("OUT OF RANGE")
      first <- start_fixed("GREGORIAN", year)
      last <- start_fixed("GREGORIAN", year + 1) - 1
      entries <- new_years(calendar, first, last)
      return(if (length(entries)) paste(entries, collapse = " ") else "NONE")
    }
    month <- as.numeric(args[3])
    if (command == "MONTHCAL") return(calendar_lines(calendar, year, month))
    bounds <- month_bounds(calendar, year, month)
    first <- bounds[1]
    last <- bounds[2]
    weekday <- match(args[5], weekdays) - 1
    if (args[4] == "LAST") {
      day <- last - (last - weekday) %% 7
    } else {
      day <- first + (weekday - first) %% 7 + 7 * (as.numeric(args[4]) - 1)
    }
    return(if (day > last) "NONE" else format_date(calendar, day))
  }
  if (command == "VALID") {
    date <- tryCatch(parse_date(calendar, args[2]),
                     error = function(e) structure(NA_real_, reason = conditionMessage(e)))
    if (is.na(date)) return(paste("NO", attr(date, "reason")))
    return(paste("YES", format_date(calendar, date)))
  }
  first <- parse_date(calendar, args[2])
  if (command == "DIFF")
    return(as.character(parse_date(args[3], args[4]) - first))
  if (command %in% c("COUNT", "SPAN")) {
    last <- parse_date(calendar, args[3])
    if (command == "SPAN") return(span_text(calendar, first, last))
    low <- min(first, last)
    high <- max(first, last)
    occurrence <- low + ((match(args[4], weekdays) - 1 - low) %% 7)
    return(as.character(if (occurrence > high) 0 else floor((high - occurrence) / 7) + 1))
  }
  if (command == "CONVERT") return(format_date(args[4], first))
  if (command == "WEEKDAY") return(weekdays[first %% 7 + 1])
  if (command == "ALL") {
    result <- character()
    for (target in calendars) {
      text <- format_date(target, first)
      if (target %in% ymd && text != "OUT OF RANGE") {
        fields <- parts_of(target, first)
        text <- paste(text, names_for(target, fields[1])[fields[2]])
      }
      result <- c(result, paste(target, text))
    }
    return(result)
  }
  if (command == "INFO") {
    fields <- parts_of(calendar, first)
    year <- fields[1]
    month <- fields[2]
    day <- fields[3]
    weekday <- weekdays[first %% 7 + 1]
    if (calendar == "FRENCH")
      weekday <- if (month <= 12) decades[(day - 1) %% 10 + 1] else festival[day]
    ordinal <- first - start_fixed(calendar, year) + 1
    length <- start_fixed(calendar, year + 1) - start_fixed(calendar, year)
    return(paste0(
      weekday, " ", day, " ", names_for(calendar, year)[month],
      " ", year, " day=", ordinal, "/", length
    ))
  }
  if (command == "ROUND")
    return(round_date(calendar, first, as.numeric(args[3]), args[4],
                      as.numeric(args[5]), args[6]))
  amount <- as.numeric(args[3])
  unit <- args[4]
  result <- switch(
    unit,
    DAYS = first + amount,
    WEEKS = first + 7 * amount,
    YEARS = shift_date(calendar, first, amount, 0),
    MONTHS = shift_date(calendar, first, 0, amount)
  )
  if (is.na(result)) "OUT OF RANGE" else format_date(calendar, result)
}

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.numeric(lines[1])
output <- character()
for (i in seq_len(count)) {
  words <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  command <- words[1]
  args <- words[-1]
  if (!(command %in% names(arity)) || length(args) != arity[[command]]) {
    output <- c(output, "INVALID COMMAND")
    next
  }
  result <- tryCatch(
    execute(command, args),
    error = function(e) {
      reason <- conditionMessage(e)
      if (reason == "COMMAND") {
        "INVALID COMMAND"
      } else if (reason == "RANGE") {
        "OUT OF RANGE"
      } else if (reason %in% c("FORMAT", "YEAR", "MONTH", "DAY", "FIELD", "WEEK")) {
        "INVALID DATE"
      } else {
        stop(e)
      }
    }
  )
  output <- c(output, result)
}
if (length(output)) cat(paste0(paste(output, collapse = "\n"), "\n"))
