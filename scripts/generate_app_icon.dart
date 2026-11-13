// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  // Create a 512x512 image
  final image = img.Image(width: 512, height: 512);

  // Background: Deep Indigo #4F46E5
  img.fill(image, color: img.ColorRgb8(79, 70, 229));

  // Draw rounded card in the center: White #FFFFFF
  img.fillRect(
    image,
    x1: 116,
    y1: 76,
    x2: 396,
    y2: 436,
    color: img.ColorRgb8(255, 255, 255),
  );

  // Draw green header bar on the card #0E9F6E
  img.fillRect(
    image,
    x1: 116,
    y1: 76,
    x2: 396,
    y2: 156,
    color: img.ColorRgb8(14, 159, 110),
  );

  // Draw lines on the document
  img.fillRect(image, x1: 156, y1: 200, x2: 320, y2: 216, color: img.ColorRgb8(23, 32, 51));
  img.fillRect(image, x1: 156, y1: 250, x2: 260, y2: 262, color: img.ColorRgb8(148, 163, 184));
  img.fillRect(image, x1: 156, y1: 290, x2: 300, y2: 302, color: img.ColorRgb8(148, 163, 184));
  img.fillRect(image, x1: 156, y1: 330, x2: 240, y2: 342, color: img.ColorRgb8(148, 163, 184));

  final dir = Directory('assets/icon');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final pngBytes = img.encodePng(image);
  File('assets/icon/ledgerly_icon.png').writeAsBytesSync(pngBytes);
  print('Ledgerly app icon generated successfully at assets/icon/ledgerly_icon.png');
}
