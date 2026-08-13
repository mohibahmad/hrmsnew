String cleanUploadedDocumentFileName(
  String rawName, {
  String fallback = 'document',
}) {
  if (rawName.trim().isEmpty) return fallback;

  var name = rawName.trim().split('?').first;
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  if (name.contains('/')) {
    name = name.split('/').last;
  }

  name = name.trim().replaceFirst(RegExp(r'^\d+_\d+_'), '');
  return name.isNotEmpty ? name : fallback;
}
