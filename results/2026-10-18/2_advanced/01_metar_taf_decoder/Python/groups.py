import units


MODIFIERS = {"AUTO": "automated", "COR": "corrected"}
DESCRIPTORS = {
    "MI": "shallow", "BC": "patches", "PR": "partial", "DR": "low drifting",
    "BL": "blowing", "SH": "showers", "TS": "thunderstorm", "FZ": "freezing",
}
PHENOMENA = {
    "DZ": "drizzle", "RA": "rain", "SN": "snow", "SG": "snow grains",
    "IC": "ice crystals", "PL": "ice pellets", "GR": "hail", "GS": "small hail",
    "UP": "unknown precipitation", "BR": "mist", "FG": "fog", "FU": "smoke",
    "VA": "volcanic ash", "DU": "dust", "SA": "sand", "HZ": "haze", "PY": "spray",
    "PO": "dust whirls", "SQ": "squalls", "FC": "funnel cloud", "SS": "sandstorm",
    "DS": "duststorm",
}
PRECIPITATION = ("DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP")
INTENSITIES = {"-": "light", "+": "heavy", "VC": "nearby"}
NO_PHENOMENON_DESCRIPTORS = ("TS", "SH")
CLOUD_AMOUNTS = {"FEW": "few", "SCT": "scattered", "BKN": "broken", "OVC": "overcast"}
CLOUD_TYPES = {"CB": "cumulonimbus", "TCU": "towering cumulus"}
CLEAR_SKIES = {"SKC": "sky clear", "CLR": "clear below 12000 ft", "NSC": "no significant cloud"}
FRACTION_DENOMINATORS = (2, 4, 8, 16)
PRESSURE_RANGES = {"A": (2500, 3150), "Q": (850, 1070)}
QUALIFIERS = ("M", "P")
RVR_TRENDS = ("U", "D", "N")
MAXIMUM_WEATHER = 3


def is_digits(text, shortest, longest):
    return shortest <= len(text) <= longest and text.isdigit()


class Wind:
    def __init__(self, variable, direction, speed, gust, unit):
        self.variable = variable
        self.direction = direction
        self.speed = speed
        self.gust = gust
        self.unit = unit

    def calm(self):
        return not self.variable and self.direction == 0 and self.speed == 0

    def has_direction(self):
        return not self.variable and not self.calm()

    def strength(self):
        return self.speed if self.gust is None else self.gust

    def in_knots(self):
        gust = None if self.gust is None else units.knots(self.gust, self.unit)
        return Wind(self.variable, self.direction, units.knots(self.speed, self.unit), gust, "KT")


class Variation:
    def __init__(self, first, second):
        self.first = first
        self.second = second


class Visibility:
    def __init__(self, kind, qualifier, meters, whole=0, numerator=0, denominator=0, joined=False):
        self.kind = kind
        self.qualifier = qualifier
        self.meters = meters
        self.whole = whole
        self.numerator = numerator
        self.denominator = denominator
        self.joined = joined

    def miles(self):
        if self.kind == "MILES":
            return units.mile_fraction(self.whole, self.numerator, self.denominator)
        return units.miles_from_meters(self.meters)

    def meter_value(self):
        if self.kind == "MILES":
            numerator, denominator = self.miles()
            return units.meters_from_miles(numerator, denominator)
        return self.meters


class Reading:
    def __init__(self, qualifier, value):
        self.qualifier = qualifier
        self.value = value


class Rvr:
    def __init__(self, runway, readings, feet, trend):
        self.runway = runway
        self.readings = readings
        self.feet = feet
        self.trend = trend


class Weather:
    def __init__(self, intensity, codes, text):
        self.intensity = intensity
        self.codes = codes
        self.text = text

    def is_nsw(self):
        return self.text == "NSW"

    def descriptor(self):
        if self.codes and self.codes[0] in DESCRIPTORS:
            return self.codes[0]
        return ""

    def phenomena(self):
        return [code for code in self.codes if code in PHENOMENA]


class Cloud:
    def __init__(self, amount, height, cloud_type, text):
        self.amount = amount
        self.height = height
        self.cloud_type = cloud_type
        self.text = text


class Temperature:
    def __init__(self, air, dew_point):
        self.air = air
        self.dew_point = dew_point


class Pressure:
    def __init__(self, unit, value):
        self.unit = unit
        self.value = value


class State:
    def __init__(self, wind=None, visibility=None, weather=None, cloud=None):
        self.wind = wind
        self.visibility = visibility
        self.weather = weather
        self.cloud = cloud


class Section:
    def __init__(self, runway_names=(), allows_nsw=False):
        self.runway_names = runway_names
        self.allows_nsw = allows_nsw
        self.state = State()
        self.modifier = ""
        self.variation = None
        self.rvrs = []
        self.temperature = None
        self.pressure = None
        self.no_trend = False

    def record(self, kind, value):
        if kind == "modifier":
            self.modifier = value
        elif kind == "wind":
            self.state.wind = value.in_knots()
        elif kind == "variation":
            self.variation = value
        elif kind == "visibility":
            self.state.visibility = value
        elif kind == "rvr":
            self.rvrs.append(value)
        elif kind == "weather":
            if self.state.weather is None:
                self.state.weather = []
            self.state.weather.append(value)
        elif kind == "cloud":
            if self.state.cloud is None:
                self.state.cloud = []
            self.state.cloud.append(value)
        elif kind == "temperature":
            self.temperature = value
        elif kind == "pressure":
            self.pressure = value
        else:
            self.no_trend = True


def parse_modifier(text):
    return text if text in MODIFIERS else None


def parse_wind(text):
    if text.endswith("KT"):
        unit = "KT"
    elif text.endswith("MPS"):
        unit = "MPS"
    else:
        return None
    body = text[:len(text) - len(unit)]
    direction = body[:3]
    speed, separator, gust = body[3:].partition("G")
    if direction != "VRB" and not is_digits(direction, 3, 3):
        return None
    if not is_digits(speed, 2, 3) or separator and not is_digits(gust, 2, 3):
        return None
    variable = direction == "VRB"
    return Wind(
        variable, 0 if variable else int(direction), int(speed),
        int(gust) if separator else None, unit,
    )


def parse_variation(text):
    if len(text) == 7 and text[3] == "V" and is_digits(text[:3], 3, 3) and is_digits(text[4:], 3, 3):
        return Variation(int(text[:3]), int(text[4:]))
    return None


def parse_fraction(text):
    numerator, separator, denominator = text.partition("/")
    if separator and is_digits(numerator, 1, 1) and is_digits(denominator, 1, 2):
        return int(numerator), int(denominator)
    return None


def parse_visibility(text):
    if text == "CAVOK":
        return Visibility("CAVOK", "P", 10000)
    if is_digits(text, 4, 4):
        if text == "9999":
            return Visibility("METERS", "P", 10000)
        return Visibility("METERS", "", int(text))
    if not text.endswith("SM"):
        return None
    number = text[:-2]
    if " " in number:
        whole, fraction_text = number.split(" ", 1)
        fraction = parse_fraction(fraction_text)
        if not is_digits(whole, 1, 1) or fraction is None:
            return None
        return Visibility("MILES", "", 0, int(whole), fraction[0], fraction[1], True)
    qualifier = number[:1] if number[:1] in QUALIFIERS else ""
    number = number[len(qualifier):]
    if is_digits(number, 1, 2):
        return Visibility("MILES", qualifier, 0, int(number))
    fraction = parse_fraction(number)
    if fraction is None:
        return None
    return Visibility("MILES", qualifier, 0, 0, fraction[0], fraction[1])


def parse_reading(text):
    qualifier = text[:1] if text[:1] in QUALIFIERS else ""
    value = text[len(qualifier):]
    if not is_digits(value, 4, 4):
        return None
    return Reading(qualifier, int(value))


def parse_rvr(text):
    if not text.startswith("R"):
        return None
    runway, separator, rest = text[1:].partition("/")
    if not separator or not is_digits(runway[:2], 2, 2) or runway[2:] not in ("", "L", "C", "R"):
        return None
    trend = rest[-1:] if rest[-1:] in RVR_TRENDS else ""
    rest = rest[:len(rest) - len(trend)]
    feet = rest.endswith("FT")
    if feet:
        rest = rest[:-2]
    first, separator, second = rest.partition("V")
    readings = [parse_reading(first)]
    if separator:
        readings.append(parse_reading(second))
    if None in readings:
        return None
    return Rvr(runway, readings, feet, trend)


def parse_weather(text):
    if text == "NSW":
        return Weather("", [], text)
    intensity = ""
    if text[:1] in ("-", "+"):
        intensity = text[:1]
    elif text.startswith("VC"):
        intensity = "VC"
    letters = text[len(intensity):]
    if not letters or len(letters) % 2 != 0:
        return None
    codes = [letters[index:index + 2] for index in range(0, len(letters), 2)]
    if any(code not in DESCRIPTORS and code not in PHENOMENA for code in codes):
        return None
    return Weather(intensity, codes, text)


def parse_cloud(text):
    if text in CLEAR_SKIES:
        return Cloud(text, None, "", text)
    if text.startswith("VV") and is_digits(text[2:], 3, 3):
        return Cloud("VV", int(text[2:]) * 100, "", text)
    amount, height, cloud_type = text[:3], text[3:6], text[6:]
    if amount in CLOUD_AMOUNTS and is_digits(height, 3, 3) and (cloud_type == "" or cloud_type in CLOUD_TYPES):
        return Cloud(amount, int(height) * 100, cloud_type, text)
    return None


def parse_celsius(text):
    negative = text.startswith("M")
    number = text[1:] if negative else text
    if not is_digits(number, 2, 2):
        return None
    return -int(number) if negative else int(number)


def parse_temperature(text):
    air, separator, dew_point = text.partition("/")
    if not separator:
        return None
    air_value = parse_celsius(air)
    dew_value = parse_celsius(dew_point)
    if air_value is None or dew_value is None:
        return None
    return Temperature(air_value, dew_value)


def parse_pressure(text):
    if text[:1] in PRESSURE_RANGES and is_digits(text[1:], 4, 4):
        return Pressure(text[0], int(text[1:]))
    return None


def parse_no_trend(text):
    return text if text == "NOSIG" else None


PARSERS = {
    "modifier": parse_modifier,
    "wind": parse_wind,
    "variation": parse_variation,
    "visibility": parse_visibility,
    "rvr": parse_rvr,
    "weather": parse_weather,
    "cloud": parse_cloud,
    "temperature": parse_temperature,
    "pressure": parse_pressure,
    "no trend": parse_no_trend,
}


def parse_group(kind, text):
    return PARSERS[kind](text)


def valid_wind(wind):
    if wind.variable:
        if wind.speed < 1:
            return False
    elif wind.direction % 10 != 0 or wind.direction > 360:
        return False
    elif (wind.direction == 0) != (wind.speed == 0):
        return False
    if wind.gust is None:
        return True
    return not wind.calm() and wind.gust > wind.speed


def valid_variation(variation, wind):
    for direction in (variation.first, variation.second):
        if direction % 10 != 0 or not 10 <= direction <= 360:
            return False
    if variation.first == variation.second:
        return False
    return wind is not None and wind.has_direction()


def valid_visibility(visibility):
    if visibility.kind != "MILES":
        return True
    if visibility.denominator == 0:
        return visibility.whole >= 1
    if visibility.joined and visibility.whole < 1:
        return False
    if visibility.denominator not in FRACTION_DENOMINATORS:
        return False
    return 1 <= visibility.numerator < visibility.denominator


def valid_rvr(rvr, runway_names):
    if rvr.runway not in runway_names:
        return False
    return len(rvr.readings) == 1 or rvr.readings[0].value < rvr.readings[1].value


def valid_weather(weather, section):
    accepted = section.state.weather or []
    if len(accepted) >= MAXIMUM_WEATHER or any(group.is_nsw() for group in accepted):
        return False
    if weather.is_nsw():
        return section.allows_nsw and not accepted
    if any(code in DESCRIPTORS for code in weather.codes[1:]):
        return False
    phenomena = weather.phenomena()
    if len(set(phenomena)) != len(phenomena):
        return False
    if not phenomena and weather.codes[0] not in NO_PHENOMENON_DESCRIPTORS:
        return False
    precipitation = [code for code in phenomena if code in PRECIPITATION]
    if weather.intensity in ("-", "+") and not precipitation:
        return False
    return len(phenomena) < 2 or len(precipitation) == len(phenomena)


def valid_cloud(cloud, accepted):
    if not accepted:
        return True
    last = accepted[-1]
    if cloud.amount not in CLOUD_AMOUNTS or last.amount not in CLOUD_AMOUNTS:
        return False
    return cloud.height > last.height


def valid_pressure(pressure):
    lowest, highest = PRESSURE_RANGES[pressure.unit]
    return lowest <= pressure.value <= highest


def valid_group(kind, value, section):
    if kind == "wind":
        return valid_wind(value)
    if kind == "variation":
        return valid_variation(value, section.state.wind)
    if kind == "visibility":
        return valid_visibility(value)
    if kind == "rvr":
        return valid_rvr(value, section.runway_names)
    if kind == "weather":
        return valid_weather(value, section)
    if kind == "cloud":
        return valid_cloud(value, section.state.cloud)
    if kind == "temperature":
        return value.dew_point <= value.air
    if kind == "pressure":
        return valid_pressure(value)
    return True
