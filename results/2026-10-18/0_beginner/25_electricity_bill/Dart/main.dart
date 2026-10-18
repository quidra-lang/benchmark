import 'dart:io';
import 'dart:math' as math;


void main() {
  final out = StringBuffer();
  var total=0;
  for(final p in [('Sato',85),('Suzuki',120),('Takahashi',254),('Tanaka',300),('Ito',438),('Watanabe',176)]) {
    final usage=p.$2;
    var bill=900+math.min(usage,120)*30;
    if(usage>120) bill+=math.min(usage-120,180)*36;
    if(usage>300) bill+=(usage-300)*40;
    total+=bill;
    out.writeln('${p.$1}: $usage kWh, $bill yen');
  }
  out.writeln('total: $total yen');
  stdout.write(out);
}
