part of 'main.dart';

bool dirty(String state) => state == 'M' || state == 'O';
(String, String) requestTransition(
  String protocol,
  String state,
  String operation,
) {
  if (protocol == 'VI') {
    if (operation == 'W') return ('BusWr', state);
    return state == 'I' ? ('BusRd', 'V') : ('', state);
  }
  if (state == 'I') {
    if (operation == 'W') return ('BusRdX', 'M');
    return ('BusRd', protocol == 'MSI' ? 'S' : 'E/S');
  }
  if (operation == 'R') return ('', state);
  return state == 'S' || state == 'O' ? ('BusUpgr', 'M') : ('', 'M');
}

(String, bool, bool) snoopTransition(
  String protocol,
  String state,
  String kind,
) {
  if (kind != 'BusRd') return ('I', kind == 'BusRdX' && dirty(state), false);
  if (protocol == 'VI') return (state, false, false);
  if (state == 'M')
    return protocol == 'MOESI' ? ('O', true, false) : ('S', true, true);
  if (state == 'O') return ('O', true, false);
  return ('S', false, false);
}
