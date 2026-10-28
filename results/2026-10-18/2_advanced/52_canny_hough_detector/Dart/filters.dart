part of 'main.dart';

Image newImage(int width, int height) =>
    List.generate(height, (_) => List.filled(width, 0));
int reference(Image image, int x, int y) =>
    image[y.clamp(0, image.length - 1).toInt()][x
        .clamp(0, image.first.length - 1)
        .toInt()];
int floorDiv(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
Image smooth(Image image, Params p) {
  final width = image.first.length,
      height = image.length,
      result = newImage(width, height),
      size = p.integer('gauss_size'),
      half = size ~/ 2,
      kernel = p['gauss_kernel'];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var total = 0;
      for (var j = 0; j < size; j++) {
        for (var i = 0; i < size; i++) {
          total +=
              kernel[j * size + i] *
              reference(image, x + i - half, y + j - half);
        }
      }
      result[y][x] = floorDiv(total, p.integer('gauss_divisor'));
    }
  }
  return result;
}

(Image, Image, Image) gradient(Image image) {
  final width = image.first.length,
      height = image.length,
      gx = newImage(width, height),
      gy = newImage(width, height),
      magnitude = newImage(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final q1 = reference(image, x - 1, y - 1),
          q2 = reference(image, x, y - 1),
          q3 = reference(image, x + 1, y - 1),
          q4 = reference(image, x - 1, y),
          q6 = reference(image, x + 1, y),
          q7 = reference(image, x - 1, y + 1),
          q8 = reference(image, x, y + 1),
          q9 = reference(image, x + 1, y + 1);
      gx[y][x] = (q3 + 2 * q6 + q9) - (q1 + 2 * q4 + q7);
      gy[y][x] = (q7 + 2 * q8 + q9) - (q1 + 2 * q2 + q3);
      magnitude[y][x] = gx[y][x].abs() + gy[y][x].abs();
    }
  }
  return (gx, gy, magnitude);
}
