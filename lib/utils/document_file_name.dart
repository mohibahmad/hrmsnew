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

  // UploadService prepends `<microseconds>_<sequence>_` to avoid collisions.
  // Strip only that generated prefix and preserve the user's exact filename,
  // including underscores and legitimate leading numbers.
  name = name.trim().replaceFirst(RegExp(r'^\d+_\d+_'), '');
  return name.isNotEmpty ? name : fallback;
}
