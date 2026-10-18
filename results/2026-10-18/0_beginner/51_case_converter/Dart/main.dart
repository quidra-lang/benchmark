import 'dart:io';


void main() {
  final out = StringBuffer();
  for(final id in ['user_name','maxRetryCount','ShoppingCartItem','background-color','get_last_login_time','isEmailAddressValid']) {
    final words=id.replaceAllMapped(RegExp('[A-Z]'),(m)=>' ${m[0]}').split(RegExp('[_ -]+')).where((w)=>w.isNotEmpty).map((w)=>w.toLowerCase()).toList();
    String cap(String s)=>s[0].toUpperCase()+s.substring(1);
    final snake=words.join('_'),camel=words.first+words.skip(1).map(cap).join(),pascal=words.map(cap).join(),kebab=words.join('-');
    out.writeln('$id: snake=$snake, camel=$camel, pascal=$pascal, kebab=$kebab');
  }
  stdout.write(out);
}
