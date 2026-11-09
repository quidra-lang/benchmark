void main() {
  var factorial = 1;
  for (var n = 0; n <= 12; n++) {
    if (n > 0) factorial *= n;
    print('$n! = $factorial');
  }
}
