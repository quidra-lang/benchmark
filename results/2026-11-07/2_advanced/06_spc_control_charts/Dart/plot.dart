import 'dart:math';
import 'variable_charts.dart';

void place(List<String> band, int position, String symbol) { band[position.clamp(0, 60).toInt()] = symbol; }
List<String> framedBand(int center) {
  final band = List.filled(61, '.'); place(band, 0, ':'); place(band, 60, ':'); place(band, center, '|'); return band;
}

String limitsBand(Limits limits, double value, bool signalled) {
  final span = limits.ucl - limits.lcl, band = framedBand((60 * ((limits.cl - limits.lcl) / span) + 0.5).floor());
  place(band, (60 * ((value - limits.lcl) / span) + 0.5).floor(), signalled ? '*' : 'o'); return band.join();
}

String cusumBand(double upper, double lower, double threshold, bool upperSignal, bool lowerSignal) {
  final band = framedBand(30);
  if (lower > 0) place(band, 30 - min(30, (30 * (lower / threshold) + 0.5).floor()), lowerSignal ? '*' : '-');
  if (upper > 0) place(band, 30 + min(30, (30 * (upper / threshold) + 0.5).floor()), upperSignal ? '*' : '+');
  return band.join();
}

String widthBand(double scale, double width, double value, double center, bool signalled) {
  final band = List.filled(61, '.'), edge = min(30, (30 * (width / scale) + 0.5).floor());
  place(band, 30, '|'); place(band, 30 - edge, ':'); place(band, 30 + edge, ':');
  place(band, 30 + (30 * ((value - center) / scale) + 0.5).floor(), signalled ? '*' : 'o'); return band.join();
}

String standardBand(double z, bool ok) {
  final band = framedBand(30); place(band, 30 + (10 * z + 0.5).floor(), ok ? 'o' : '*'); return band.join();
}
