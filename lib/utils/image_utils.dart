import 'dart:developer' as developer;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

/// Resmi sıkıştır ve optimize et
Future<List<int>> compressImage(XFile imageFile, {int quality = 85, int maxWidth = 1200}) async {
  try {
    final bytes = await imageFile.readAsBytes();
    
    // Resmi decode et
    final image = img.decodeImage(bytes);
    if (image == null) return bytes.toList();
    
    // Boyutu küçült (width > maxWidth ise)
    img.Image resized = image;
    if (image.width > maxWidth) {
      resized = img.copyResize(
        image,
        width: maxWidth,
        height: (image.height * maxWidth ~/ image.width),
      );
    }
    
    // JPEG olarak sıkıştır
    final compressed = img.encodeJpg(resized, quality: quality);
    
    // Sıkıştırma oranını log et
    final ratio = (1 - (compressed.length / bytes.length)) * 100;
    developer.log('Resim sıkıştırıldı: %${ratio.toStringAsFixed(1)} küçültüldü (${bytes.length} → ${compressed.length} bytes)', name: 'image_utils');
    
    return compressed;
  } catch (e) {
    developer.log('Resim sıkıştırma hatası: $e - orijinal kullanılacak', name: 'image_utils');
    final bytes = await imageFile.readAsBytes();
    return bytes.toList();
  }
}

/// Mehrere Bilder sıkıştır
Future<List<List<int>>> compressImages(
  List<XFile> imageFiles, {
  int quality = 85,
  int maxWidth = 1200,
}) async {
  final results = <List<int>>[];
  
  for (final file in imageFiles) {
    final compressed = await compressImage(file, quality: quality, maxWidth: maxWidth);
    results.add(compressed);
  }
  
  return results;
}

/// Resmin boyutunu insan okunabilir formatta döndür
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
