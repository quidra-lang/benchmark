import 'dart:io';


void main() {
  final out = StringBuffer();
  const codes=['.-', '-...', '-.-.', '-..', '.', '..-.', '--.', '....', '..', '.---', '-.-', '.-..', '--', '-.', '---', '.--.', '--.-', '.-.', '...', '-', '..-', '...-', '.--', '-..-', '-.--', '--..', '-----', '.----', '..---', '...--', '....-', '.....', '-....', '--...', '---..', '----.'];const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';const message='MEET ME AT PIER 9 AT 1745';
  final encoded=message.split(' ').map((w)=>w.split('').map((c)=>codes[alphabet.indexOf(c)]).join(' ')).join(' / ');
  final decoded=encoded.split(' / ').map((w)=>w.split(' ').map((c)=>alphabet[codes.indexOf(c)]).join()).join(' ');
  out.writeln(encoded);out.writeln(decoded);
  stdout.write(out);
}
