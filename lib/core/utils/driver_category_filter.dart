/// استخراج معرّف فئة التسعير من صف سائق (قائمة الإدارة).
int transTypeIdFromDriverRow(Map<String, dynamic> row) {
  final direct = int.tryParse(
        row['transTypeId']?.toString() ?? row['trans_type_id']?.toString() ?? '',
      ) ??
      0;
  if (direct > 0) return direct;
  final t = row['transType'] ?? row['trans_type'];
  if (t is Map) {
    return int.tryParse(t['id']?.toString() ?? '') ?? 0;
  }
  return 0;
}
