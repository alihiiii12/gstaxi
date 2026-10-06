import 'vehicle_type_options.dart';

/// نص تحت اسم السائق: لوحة، فئة السيارة، هاتف، واختياريًا مسافة (قوائم الزبون والإدارة).
/// لا يُضمّن تقدير تكلفة هنا؛ التسعيرة المعتمدة هي تسعيرة الفئة من الطلب.
String bookingDriverCardSubtitle(Map<String, dynamic> row) {
  final plate = row['carNumber']?.toString().trim() ?? '';
  final cat = row['car_category_name']?.toString().trim() ??
      row['carCategoryName']?.toString().trim() ??
      '';
  final model = (row['vehicle_model'] ?? row['vehicleModel'])?.toString().trim() ?? '';
  final phone = row['number']?.toString().trim() ?? '';
  final km = row['distance_from_pickup_km'];

  final lines = <String>[
    'لوحة: ${plate.isEmpty ? '—' : plate}',
    if (model.isNotEmpty) 'نوع السيارة: $model',
    if (cat.isNotEmpty) 'فئة التسعير: $cat',
    if (phone.isNotEmpty) 'هاتف السائق: $phone',
  ];
  if (km != null) {
    lines.add('تقريباً $km كم من موقعك');
  }
  return lines.join('\n');
}

/// صف سائق في لوحة الإدارة (البيانات من `drivers/index`).
String adminDriverCardSubtitle(
    Map<String, dynamic> row, Map<String, dynamic> user) {
  final plate = row['car_number']?.toString().trim() ??
      row['carNumber']?.toString().trim() ??
      '';

  Map<String, dynamic>? trans;
  final a = row['transType'];
  if (a is Map<String, dynamic>) {
    trans = a;
  } else if (a is Map) {
    trans = Map<String, dynamic>.from(a);
  }
  final b = row['trans_type'];
  if (trans == null) {
    if (b is Map<String, dynamic>) {
      trans = b;
    } else if (b is Map) {
      trans = Map<String, dynamic>.from(b);
    }
  }

  final cat = trans?['name']?.toString().trim() ?? '';
  final model =
      (row['vehicle_model'] ?? row['vehicleModel'])?.toString().trim() ?? '';
  final phone = user['number']?.toString().trim() ?? '';

  final vType = vehicleTypeLabelAr(row['type']?.toString());
  return [
    'لوحة: ${plate.isEmpty ? '—' : plate}',
    if (vType.isNotEmpty) 'نوع المركبة: $vType',
    if (model.isNotEmpty) 'ماركة/موديل: $model',
    if (cat.isNotEmpty) 'فئة التسعير: $cat',
    if (phone.isNotEmpty) 'هاتف السائق: $phone',
  ].join('\n');
}

/// الشريط الأخضر للرحلة النشطة (كائن driver ضمن الطلب).
String tripActiveStripDriverSubtitle(
  Map<String, dynamic>? driverMap,
  Map<String, dynamic>? userMap,
) {
  if (driverMap == null || userMap == null) {
    return '';
  }
  return adminDriverCardSubtitle(driverMap, userMap);
}
