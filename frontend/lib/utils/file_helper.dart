import 'file_helper_stub.dart'
    if (dart.library.html) 'file_helper_web.dart' as impl;

void downloadFile(String content, String filename, String mimeType) {
  impl.downloadFile(content, filename, mimeType);
}

Future<String?> pickJsonFile() {
  return impl.pickJsonFile();
}
