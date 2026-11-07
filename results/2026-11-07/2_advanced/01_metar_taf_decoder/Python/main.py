import os

from groups import (
    CLEAR_SKIES, CLOUD_AMOUNTS, CLOUD_TYPES, DESCRIPTORS, INTENSITIES, MODIFIERS, PHENOMENA,
    Section, is_digits, parse_fraction, parse_group, valid_group,
)
import metar
import taf
import units
from verification import CATEGORIES, Contingency, chosen_forecast, covers


REPORT_KINDS = ("METAR", "SPECI", "TAF")
HEADER_ITEMS = {
    "METAR": ("station", "time"),
    "SPECI": ("station", "time"),
    "TAF": ("station", "time", "validity"),
}
TAF_MODIFIERS = {"AMD": "amended", "COR": "corrected"}
MAXIMUM_VALIDITY = 1800
STANDARD_INHG = 2992
CEILING_AMOUNTS = ("BKN", "OVC", "VV")
TREND_WORDS = {"BECMG": "becoming", "TEMPO": "temporarily"}
TIME_WORDS = {"FM": "from", "TL": "until", "AT": "at"}
RVR_TREND_WORDS = {"U": "rising", "D": "falling", "N": "no change"}
QUALIFIER_WORDS = {"": "", "M": "less than ", "P": "more than "}
SPECI_SHIFT_ANGLE = 45
AMENDMENT_SHIFT_ANGLE = 60
BUCKET_HOURS = 6
BUCKET_COUNT = 5


class Runway:
    def __init__(self, name, heading):
        self.name = name
        self.heading = heading


class Station:
    def __init__(self, code, elevation, runways, name):
        self.code = code
        self.elevation = elevation
        self.runways = runways
        self.name = name

    def runway_names(self):
        return [runway.name for runway in self.runways]

    def title(self):
        return f"{self.code} ({self.name})"


class Settings:
    def __init__(self, calendar, crosswind_limit, tailwind_limit, verified):
        self.calendar = calendar
        self.crosswind_limit = crosswind_limit
        self.tailwind_limit = tailwind_limit
        self.verified = verified


class Report:
    def __init__(self, number, words):
        self.number = number
        self.words = words
        self.errors = []


class Header:
    def __init__(self, kind):
        self.kind = kind
        self.modifier = ""
        self.station = None
        self.time = None
        self.start = None
        self.end = None
        self.body = []


class RunwayWind:
    def __init__(self, runway, mean, gust, usable):
        self.runway = runway
        self.mean = mean
        self.gust = gust
        self.usable = usable


class Observation:
    def __init__(self, number, header):
        self.number = number
        self.kind = header.kind
        self.station = header.station
        self.time = header.time
        self.main = Section(header.station.runway_names())
        self.trends = []
        self.sea_level_pressures = []
        self.precise_temperatures = []
        self.ceiling = None
        self.category = ""
        self.pressure_altitude = None
        self.density_altitude = None
        self.runway_winds = None
        self.speci_reasons = []


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_stations(path):
    stations = {}
    for line in read_lines(path):
        code, elevation, runway_list, name = line.split(" ", 3)
        runways = []
        for entry in runway_list.split(","):
            runway_name, heading = entry.split("/")
            runways.append(Runway(runway_name, int(heading)))
        stations[code] = Station(code, int(elevation), runways, name)
    return stations


def read_settings(path):
    values = {}
    for line in read_lines(path):
        key, value = line.split(" ", 1)
        values[key] = value
    return Settings(
        units.Calendar(int(values["YEAR"]), int(values["MONTH"])),
        int(values["CROSSWIND_LIMIT"]), int(values["TAILWIND_LIMIT"]),
        values["VERIFY"].split(" "),
    )


def read_reports(path):
    reports = []
    for line in read_lines(path):
        if line.startswith(" "):
            reports[-1].words.extend(line.split())
        else:
            reports.append(Report(len(reports) + 1, line.split()))
    return reports


def parse_time(text, calendar):
    if len(text) != 7 or not is_digits(text[:6], 6, 6) or text[6] != "Z":
        return None
    day, hour, minute = int(text[:2]), int(text[2:4]), int(text[4:6])
    if not 1 <= day <= calendar.days or hour > 23 or minute > 59:
        return None
    return units.day_minutes(day, hour, minute)


def read_header_item(header, item, word, stations, calendar):
    if item == "station":
        header.station = stations.get(word)
        return header.station is not None
    if item == "time":
        header.time = parse_time(word, calendar)
        return header.time is not None
    period = taf.parse_period(word, units.day_of(header.time), calendar)
    if period is None or period[1] > period[0] + MAXIMUM_VALIDITY:
        return False
    header.start, header.end = period
    return True


def parse_header(report, stations, calendar):
    words = report.words
    if words[0] not in REPORT_KINDS:
        report.errors.append((1, f'rejected report, invalid type "{words[0]}"'))
        return None
    header = Header(words[0])
    index = 1
    if header.kind == "TAF" and len(words) > 1 and words[1] in TAF_MODIFIERS:
        header.modifier = words[1]
        index = 2
    for item in HEADER_ITEMS[header.kind]:
        if index == len(words):
            report.errors.append((index + 1, f"rejected report, missing {item}"))
            return None
        if not read_header_item(header, item, words[index], stations, calendar):
            report.errors.append((index + 1, f'rejected report, invalid {item} "{words[index]}"'))
            return None
        index += 1
    header.body = join_groups(words, index)
    return header


def is_fraction_word(word):
    return word.endswith("SM") and parse_fraction(word[:-2]) is not None


def join_groups(words, start):
    groups = []
    index = start
    while index < len(words):
        word = words[index]
        following = words[index + 1] if index + 1 < len(words) else ""
        if len(word) == 1 and word.isdigit() and is_fraction_word(following):
            groups.append((index + 1, word + " " + following))
            index += 2
        else:
            groups.append((index + 1, word))
            index += 1
    return groups


def find_slot(slots, first, last, text):
    for index in range(first, last):
        value = parse_group(slots[index][0], text)
        if value is not None:
            return index, value
    return -1, None


def match_groups(groups, slots, section, errors):
    current = 0
    for position, text in groups:
        index, value = find_slot(slots, current, len(slots), text)
        if index < 0:
            earlier, _ = find_slot(slots, 0, current, text)
            label = "unknown group" if earlier < 0 else "out of order group"
            errors.append((position, f'{label} "{text}"'))
            continue
        kind, repeatable = slots[index]
        if not valid_group(kind, value, section):
            errors.append((position, f'invalid group "{text}"'))
            continue
        section.record(kind, value)
        if kind == "visibility" and value.kind == "CAVOK":
            section.state.weather = []
            section.state.cloud = []
            current = [slot_kind for slot_kind, _ in slots].index("cloud") + 1
        elif not repeatable:
            current = index + 1
        else:
            current = index


def decode_observation(report, header):
    observation = Observation(report.number, header)
    main_part, trend_part, remarks = metar.split_body(header.body)
    match_groups(main_part, metar.MAIN_SLOTS, observation.main, report.errors)
    for groups in metar.trend_sections(trend_part):
        trend = metar.read_trend(groups, report.errors)
        if trend is not None:
            trend.section = Section(allows_nsw=True)
            match_groups(trend.groups, metar.TREND_SLOTS, trend.section, report.errors)
            observation.trends.append(trend)
    observation.sea_level_pressures, observation.precise_temperatures = metar.read_remarks(remarks)
    return observation


def forecast_state(groups, allows_nsw, errors):
    section = Section(allows_nsw=allows_nsw)
    match_groups(groups, taf.TAF_SLOTS, section, errors)
    return section.state


def decode_forecast(report, header, calendar):
    forecast = taf.Taf(
        report.number, header.station, header.time, header.modifier, header.start, header.end
    )
    base_groups, forecast.changes = taf.split_changes(forecast, header.body, calendar, report.errors)
    forecast.base = forecast_state(base_groups, False, report.errors)
    for change in forecast.changes:
        change.state = forecast_state(change.groups, True, report.errors)
    return forecast


def ceiling(state):
    for cloud in state.cloud or []:
        if cloud.amount in CEILING_AMOUNTS:
            return cloud.height
    return None


def flight_category(state):
    height = ceiling(state)
    numerator, denominator = (1, 0) if state.visibility is None else state.visibility.miles()
    if height is not None and height < 500 or numerator < denominator:
        return "LIFR"
    if height is not None and height < 1000 or numerator < 3 * denominator:
        return "IFR"
    if height is not None and height <= 3000 or numerator <= 5 * denominator:
        return "MVFR"
    return "VFR"


def inhg_value(pressure):
    if pressure.unit == "A":
        return pressure.value
    return units.inhg_from_hpa(pressure.value)


def wind_components(direction, heading, speed):
    angle = direction - heading
    return speed * units.cos(angle) // 1000, speed * units.sin(angle) // 1000


def runway_winds(station, wind, settings):
    if wind is None or not wind.has_direction():
        return None
    winds = []
    for runway in station.runways:
        mean = wind_components(wind.direction, runway.heading, wind.speed)
        gust = None
        if wind.gust is not None:
            gust = wind_components(wind.direction, runway.heading, wind.gust)
        headwind, crosswind = mean if gust is None else gust
        usable = abs(crosswind) <= settings.crosswind_limit and -headwind <= settings.tailwind_limit
        winds.append(RunwayWind(runway, mean, gust, usable))
    return winds


def preferred_runway(winds):
    preferred = None
    for wind in winds:
        if wind.usable and (preferred is None or wind.mean[0] > preferred.mean[0]):
            preferred = wind
    return preferred


def direction_difference(first, second):
    difference = abs(first - second) % 360
    return min(difference, 360 - difference)


def wind_changes(earlier, later, angle):
    if earlier is None or later is None:
        return []
    changes = []
    if (
        earlier.has_direction() and later.has_direction()
        and max(earlier.speed, later.speed) >= 10
        and direction_difference(earlier.direction, later.direction) >= angle
    ):
        changes.append("wind shift")
    if abs(earlier.speed - later.speed) >= 10:
        changes.append("wind speed")
    return changes


def has_thunderstorm(state):
    return any(group.descriptor() == "TS" for group in state.weather or [])


def has_freezing_precipitation(state):
    for group in state.weather or []:
        phenomena = group.phenomena()
        if group.descriptor() == "FZ" and ("DZ" in phenomena or "RA" in phenomena):
            return True
    return False


def speci_reasons(previous, current):
    if previous is None:
        return ["no previous report"]
    before, now = previous.main.state, current.main.state
    reasons = []
    if previous.category != current.category:
        reasons.append(f"category {previous.category} to {current.category}")
    reasons.extend(wind_changes(before.wind, now.wind, SPECI_SHIFT_ANGLE))
    thunderstorm = has_thunderstorm(now)
    if thunderstorm != has_thunderstorm(before):
        reasons.append("thunderstorm began" if thunderstorm else "thunderstorm ended")
    freezing = has_freezing_precipitation(now)
    if freezing != has_freezing_precipitation(before):
        reasons.append("freezing precipitation began" if freezing else "freezing precipitation ended")
    return reasons or ["no criteria met"]


def derive(observation, previous, settings):
    main = observation.main
    observation.ceiling = ceiling(main.state)
    observation.category = flight_category(main.state)
    if main.pressure is not None:
        altitude = observation.station.elevation + (STANDARD_INHG - inhg_value(main.pressure)) * 10
        observation.pressure_altitude = altitude
        if main.temperature is not None:
            correction = (120 * (1000 * main.temperature.air - 15000 + 2 * altitude)) // 1000
            observation.density_altitude = altitude + correction
    observation.runway_winds = runway_winds(observation.station, main.state.wind, settings)
    if observation.kind == "SPECI":
        observation.speci_reasons = speci_reasons(previous, observation)


def wind_phrase(wind):
    if wind.calm():
        text = "calm"
    elif wind.variable:
        text = f"variable at {wind.speed} KT"
    else:
        text = f"{wind.direction:03d} degrees at {wind.speed} KT"
    if wind.gust is not None:
        text += f" gusting {wind.gust} KT"
    return text


def mile_number(visibility):
    if visibility.denominator == 0:
        return str(visibility.whole)
    fraction = f"{visibility.numerator}/{visibility.denominator}"
    if visibility.whole == 0:
        return fraction
    return f"{visibility.whole} {fraction}"


def visibility_phrase(visibility):
    if visibility.kind == "CAVOK":
        return "10 km or more (CAVOK)"
    if visibility.kind == "METERS":
        return "10 km or more" if visibility.qualifier == "P" else f"{visibility.meters} m"
    return QUALIFIER_WORDS[visibility.qualifier] + mile_number(visibility) + " SM"


def weather_phrase(weather):
    if weather.is_nsw():
        return "no significant weather"
    parts = []
    if weather.intensity:
        parts.append(INTENSITIES[weather.intensity])
    if weather.descriptor():
        parts.append(DESCRIPTORS[weather.descriptor()])
    phenomena = weather.phenomena()
    if phenomena:
        parts.append(" and ".join(PHENOMENA[code] for code in phenomena))
    return " ".join(parts)


def cloud_phrase(cloud):
    if cloud.amount in CLEAR_SKIES:
        return CLEAR_SKIES[cloud.amount]
    if cloud.amount == "VV":
        return f"vertical visibility {cloud.height} ft"
    text = f"{CLOUD_AMOUNTS[cloud.amount]} at {cloud.height} ft"
    if cloud.cloud_type:
        text += " " + CLOUD_TYPES[cloud.cloud_type]
    return text


def summary(state):
    parts = []
    if state.wind is not None:
        parts.append("wind " + wind_phrase(state.wind))
    if state.visibility is not None:
        parts.append("visibility " + visibility_phrase(state.visibility))
    if state.weather:
        parts.append("weather " + ", ".join(weather_phrase(group) for group in state.weather))
    if state.cloud:
        parts.append("cloud " + ", ".join(cloud_phrase(group) for group in state.cloud))
    return "; ".join(parts) if parts else "no conditions"


def wind_code(wind):
    if wind.calm():
        return "00000KT"
    direction = "VRB" if wind.variable else f"{wind.direction:03d}"
    gust = "" if wind.gust is None else f"G{wind.gust:02d}"
    return f"{direction}{wind.speed:02d}{gust}KT"


def visibility_code(visibility):
    if visibility.kind == "CAVOK":
        return "CAVOK"
    if visibility.kind == "METERS":
        return "9999" if visibility.qualifier == "P" else f"{visibility.meters:04d}"
    return visibility.qualifier + mile_number(visibility) + "SM"


def tokens(state):
    parts = []
    if state.wind is not None:
        parts.append(wind_code(state.wind))
    if state.visibility is not None:
        parts.append(visibility_code(state.visibility))
    for group in state.weather or []:
        if not group.is_nsw():
            parts.append(group.text)
    for group in state.cloud or []:
        parts.append(group.text)
    parts.append(flight_category(state))
    return " ".join(parts)


def tenths_text(value):
    sign = "-" if value < 0 else ""
    return f"{sign}{abs(value) // 10}.{abs(value) % 10}"


def inhg_text(value):
    return f"{value // 100}.{value % 100:02d}"


def component_phrase(headwind, crosswind):
    if headwind < 0:
        text = f"tailwind {-headwind} KT"
    else:
        text = f"headwind {headwind} KT"
    if crosswind > 0:
        return text + f", crosswind {crosswind} KT from right"
    if crosswind < 0:
        return text + f", crosswind {-crosswind} KT from left"
    return text + ", crosswind 0 KT"


def wind_line(section):
    if section.state.wind is None:
        return "not reported"
    text = wind_phrase(section.state.wind)
    if section.variation is not None:
        first, second = section.variation.first, section.variation.second
        text += f", varying between {first:03d} and {second:03d} degrees"
    return text


def rvr_phrase(rvr):
    readings = [QUALIFIER_WORDS[reading.qualifier] + str(reading.value) for reading in rvr.readings]
    text = f"runway {rvr.runway} "
    if len(readings) == 1:
        text += readings[0]
    else:
        text += f"between {readings[0]} and {readings[1]}"
    text += " ft" if rvr.feet else " m"
    if rvr.trend:
        text += ", " + RVR_TREND_WORDS[rvr.trend]
    return text


def cloud_texts(state):
    if state.visibility is not None and state.visibility.kind == "CAVOK":
        return ["no significant cloud"]
    if state.cloud is None:
        return ["not reported"]
    return [cloud_phrase(group) for group in state.cloud]


def temperature_phrase(temperature):
    if temperature is None:
        return "not reported"
    spread = temperature.air - temperature.dew_point
    return f"{temperature.air} C, dew point {temperature.dew_point} C, spread {spread} C"


def altimeter_phrase(pressure):
    if pressure is None:
        return "not reported"
    inhg = inhg_text(inhg_value(pressure))
    if pressure.unit == "A":
        return f"{inhg} inHg ({units.hpa_from_inhg(pressure.value)} hPa)"
    return f"{pressure.value} hPa ({inhg} inHg)"


def trend_phrase(trend):
    text = TREND_WORDS[trend.kind]
    for prefix, hour, minute in trend.times:
        text += f" {TIME_WORDS[prefix]} {hour:02d}:{minute:02d}Z"
    return f"{text}: {summary(trend.section.state)}"


def altitude_text(altitude):
    return "not available" if altitude is None else f"{altitude} ft"


def runway_lines(winds):
    if winds is None:
        return ["  runway wind: not computed"]
    lines = []
    for wind in winds:
        text = f"  runway {wind.runway.name}: {component_phrase(*wind.mean)}"
        if wind.gust is not None:
            text += "; gusts " + component_phrase(*wind.gust)
        lines.append(text)
    usable = [wind.runway.name for wind in winds if wind.usable]
    preferred = preferred_runway(winds)
    lines.append("  usable runways: " + (" ".join(usable) if usable else "none"))
    lines.append("  preferred runway: " + ("none" if preferred is None else preferred.runway.name))
    return lines


def observation_lines(observation, calendar):
    main = observation.main
    state = main.state
    lines = [
        f"REPORT {observation.number}: {observation.kind} {observation.station.title()}",
        "  time: " + calendar.stamp(observation.time),
    ]
    if main.modifier:
        lines.append("  modifier: " + MODIFIERS[main.modifier])
    lines.append("  wind: " + wind_line(main))
    if state.visibility is None:
        lines.append("  visibility: not reported")
    else:
        lines.append("  visibility: " + visibility_phrase(state.visibility))
    for rvr in main.rvrs:
        lines.append("  runway visual range: " + rvr_phrase(rvr))
    for group in state.weather or []:
        lines.append("  weather: " + weather_phrase(group))
    for text in cloud_texts(state):
        lines.append("  cloud: " + text)
    lines.append("  temperature: " + temperature_phrase(main.temperature))
    lines.append("  altimeter: " + altimeter_phrase(main.pressure))
    if main.no_trend:
        lines.append("  trend: no significant change")
    for trend in observation.trends:
        lines.append("  trend: " + trend_phrase(trend))
    for pressure in observation.sea_level_pressures:
        lines.append(f"  sea level pressure: {tenths_text(pressure)} hPa")
    for air, dew_point in observation.precise_temperatures:
        lines.append(f"  precise temperature: {tenths_text(air)} C, dew point {tenths_text(dew_point)} C")
    if observation.ceiling is None:
        lines.append("  ceiling: none")
    else:
        lines.append(f"  ceiling: {observation.ceiling} ft")
    lines.append("  flight category: " + observation.category)
    lines.append("  pressure altitude: " + altitude_text(observation.pressure_altitude))
    lines.append("  density altitude: " + altitude_text(observation.density_altitude))
    lines.extend(runway_lines(observation.runway_winds))
    if observation.kind == "SPECI":
        lines.append("  speci check: " + ", ".join(observation.speci_reasons))
    return lines


def forecast_lines(forecast, calendar):
    lines = [
        f"REPORT {forecast.number}: TAF {forecast.station.title()}",
        "  issued: " + calendar.stamp(forecast.issue),
    ]
    if forecast.modifier:
        lines.append("  modifier: " + TAF_MODIFIERS[forecast.modifier])
    lines.append(f"  valid: {calendar.stamp(forecast.start)} to {calendar.stamp(forecast.end)}")
    lines.append("  base: " + summary(forecast.base))
    for change in forecast.changes:
        if change.kind == "FM":
            period = calendar.stamp(change.start)
        else:
            period = f"{calendar.stamp(change.start)} to {calendar.stamp(change.end)}"
        lines.append(f"  {change.kind} {period}: {summary(change.state)}")
    return lines


def category_lines(observations, calendar):
    lines = ["station,time,ceiling,visibility,category"]
    for observation in observations:
        visibility = observation.main.state.visibility
        ceiling_text = "NONE" if observation.ceiling is None else str(observation.ceiling)
        if visibility is None:
            visibility_text = "NONE"
        else:
            visibility_text = visibility.qualifier + str(visibility.meter_value())
        lines.append(",".join((
            observation.station.code, calendar.stamp(observation.time),
            ceiling_text, visibility_text, observation.category,
        )))
    return lines


def category_counts(categories):
    return ", ".join(f"{name} {categories.count(name)}" for name in CATEGORIES)


def timeline_lines(forecast, calendar):
    lines = [
        f"TAF {forecast.station.code} issued {calendar.stamp(forecast.issue)} "
        f"valid {calendar.stamp(forecast.start)} to {calendar.stamp(forecast.end)}"
    ]
    categories = []
    for hour in range(forecast.start, forecast.end, 60):
        prevailing = taf.prevailing_state(forecast, hour)
        line = f"{calendar.stamp(hour)} {tokens(prevailing)}"
        for kind, state in taf.temporary_states(forecast, hour):
            line += f" | {kind} {tokens(state)}"
        lines.append(line)
        categories.append(flight_category(prevailing))
    lines.append("summary: " + category_counts(categories))
    return lines


def extreme_lines(observations, calendar):
    coldest = warmest = windiest = lowest_ceiling = lowest_visibility = None
    for observation in observations:
        temperature = observation.main.temperature
        if temperature is not None:
            if coldest is None or temperature.air < coldest.main.temperature.air:
                coldest = observation
            if warmest is None or temperature.air > warmest.main.temperature.air:
                warmest = observation
        wind = observation.main.state.wind
        if wind is not None and (
            windiest is None or wind.strength() > windiest.main.state.wind.strength()
        ):
            windiest = observation
        if observation.ceiling is not None and (
            lowest_ceiling is None or observation.ceiling < lowest_ceiling.ceiling
        ):
            lowest_ceiling = observation
        visibility = observation.main.state.visibility
        if visibility is not None and (
            lowest_visibility is None
            or units.fraction_less(visibility.miles(), lowest_visibility.main.state.visibility.miles())
        ):
            lowest_visibility = observation
    extremes = (
        ("lowest temperature", coldest, lambda found: f"{found.main.temperature.air} C"),
        ("highest temperature", warmest, lambda found: f"{found.main.temperature.air} C"),
        ("strongest wind", windiest, lambda found: wind_phrase(found.main.state.wind)),
        ("lowest ceiling", lowest_ceiling, lambda found: f"{found.ceiling} ft"),
        ("lowest visibility", lowest_visibility,
         lambda found: visibility_phrase(found.main.state.visibility)),
    )
    lines = []
    for label, found, describe in extremes:
        if found is None:
            lines.append(label + ": not available")
        else:
            lines.append(f"{label}: {describe(found)} at {calendar.stamp(found.time)}")
    return lines


def table_row(label, cells):
    return f"{label:<8}" + "".join(f"{cell:>6}" for cell in cells)


def table_lines(contingency):
    lines = [table_row("forecast", CATEGORIES + ("total",))]
    for index, category in enumerate(CATEGORIES):
        lines.append(table_row(category, contingency.table[index] + [contingency.row_total(index)]))
    totals = [contingency.column_total(index) for index in range(len(CATEGORIES))]
    lines.append(table_row("total", totals + [contingency.total()]))
    return lines


def bucket_lines(observations, forecasts):
    pairs = [0] * BUCKET_COUNT
    hits = [0] * BUCKET_COUNT
    for forecast in forecasts:
        for observation in observations:
            if not covers(forecast, observation.time):
                continue
            hour = units.hour_mark(observation.time)
            bucket = (hour - forecast.start) // 60 // BUCKET_HOURS
            pairs[bucket] += 1
            if flight_category(taf.prevailing_state(forecast, hour)) == observation.category:
                hits[bucket] += 1
    lines = []
    for bucket in range(BUCKET_COUNT):
        first = bucket * BUCKET_HOURS
        rate = units.fraction_text(hits[bucket], pairs[bucket])
        lines.append(f"hours {first}-{first + BUCKET_HOURS - 1}: {rate}")
    return lines


def amendment_reasons(observation, expected, alternatives, forecast_wind):
    reasons = []
    if observation.category not in alternatives:
        reasons.append(f"category {observation.category}, forecast {expected}")
    wind = observation.main.state.wind
    if wind_changes(forecast_wind, wind, AMENDMENT_SHIFT_ANGLE):
        reasons.append(f"wind {wind_code(wind)}, forecast {wind_code(forecast_wind)}")
    return "; ".join(reasons)


def verification_lines(station, observations, forecasts, calendar):
    observed = [item for item in observations if item.station is station]
    issued = [item for item in forecasts if item.station is station]
    metar_count = sum(item.kind == "METAR" for item in observed)
    lines = [
        "station " + station.title(),
        f"reports: METAR {metar_count}, SPECI {len(observed) - metar_count}",
        "observed categories: " + category_counts([item.category for item in observed]),
    ]
    lines.extend(extreme_lines(observed, calendar))
    contingency = Contingency()
    no_forecast = 0
    amendments = []
    for observation in observed:
        forecast = chosen_forecast(issued, observation.time)
        if forecast is None:
            no_forecast += 1
            continue
        hour = units.hour_mark(observation.time)
        prevailing = taf.prevailing_state(forecast, hour)
        expected = flight_category(prevailing)
        alternatives = [expected]
        for _, state in taf.temporary_states(forecast, hour):
            alternatives.append(flight_category(state))
        contingency.add(expected, observation.category, observation.category in alternatives)
        reasons = amendment_reasons(observation, expected, alternatives, prevailing.wind)
        if reasons:
            amendments.append(f"amendment {calendar.stamp(observation.time)}: {reasons}")
    lines.append(f"verified: {contingency.total()}")
    lines.append(f"no forecast: {no_forecast}")
    lines.extend(table_lines(contingency))
    lines.append("hit rate: " + units.fraction_text(*contingency.hits()))
    lines.append(
        "hit rate with temporary groups: " + units.fraction_text(*contingency.hits_with_temporary())
    )
    lines.append("heidke skill score: " + units.fraction_text(*contingency.skill_score()))
    for index, category in enumerate(CATEGORIES):
        detection = units.fraction_text(*contingency.detection(index))
        false_alarm = units.fraction_text(*contingency.false_alarm(index))
        lines.append(f"{category}: pod {detection}, far {false_alarm}")
    lines.extend(bucket_lines(observed, issued))
    lines.extend(amendments)
    return lines


def error_lines(reports):
    lines = []
    for report in reports:
        for position, message in sorted(report.errors, key=lambda error: error[0]):
            lines.append(f"report {report.number} word {position}: {message}")
    return lines


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def write_file(path, lines):
    with open(path, "w") as file:
        file.write("".join(line + "\n" for line in lines))


def main():
    stations = read_stations("input/stations.txt")
    settings = read_settings("input/params.txt")
    calendar = settings.calendar
    reports = read_reports("input/reports.txt")
    observations = []
    forecasts = []
    decoded = []
    latest = {}
    for report in reports:
        header = parse_header(report, stations, calendar)
        if header is None:
            continue
        if header.kind == "TAF":
            forecast = decode_forecast(report, header, calendar)
            forecasts.append(forecast)
            decoded.append(forecast_lines(forecast, calendar))
        else:
            observation = decode_observation(report, header)
            derive(observation, latest.get(header.station.code), settings)
            latest[header.station.code] = observation
            observations.append(observation)
            decoded.append(observation_lines(observation, calendar))
    os.makedirs("output", exist_ok=True)
    write_file("output/decoded.txt", join_blocks(decoded))
    write_file("output/categories.csv", category_lines(observations, calendar))
    write_file(
        "output/taf_timeline.txt",
        join_blocks([timeline_lines(forecast, calendar) for forecast in forecasts]),
    )
    write_file("output/verification.txt", join_blocks([
        verification_lines(stations[code], observations, forecasts, calendar)
        for code in settings.verified
    ]))
    write_file("output/errors.txt", error_lines(reports))


if __name__ == "__main__":
    main()
