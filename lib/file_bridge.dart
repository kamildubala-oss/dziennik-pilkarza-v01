import 'package:flutter/services.dart';

/// Operacje na plikach przez natywny kod Androida (MainActivity.kt):
/// zapis w wybranym folderze, otwarcie pliku i udostępnienie.
class FileBridge {
  FileBridge._();

  static const MethodChannel _ch = MethodChannel('dziennik/files');

  /// Otwiera systemowe okno "Zapisz jako". Zwraca true po zapisaniu,
  /// false gdy użytkownik anulował.
  static Future<bool> saveFile(
      String name, String mime, Uint8List bytes) async {
    final r = await _ch.invokeMethod<bool>(
      'saveFile',
      <String, dynamic>{'name': name, 'mime': mime, 'bytes': bytes},
    );
    return r == true;
  }

  /// Otwiera systemowe okno wyboru pliku. Zwraca zawartość lub null.
  static Future<Uint8List?> openFile() =>
      _ch.invokeMethod<Uint8List>('openFile');

  /// Systemowe okno "Udostępnij" (e-mail, Dysk Google, komunikatory...).
  static Future<void> shareFile(String name, String mime, Uint8List bytes) =>
      _ch.invokeMethod<bool>(
        'shareFile',
        <String, dynamic>{'name': name, 'mime': mime, 'bytes': bytes},
      );
}
