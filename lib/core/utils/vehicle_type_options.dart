/// نوع المركبة (عمود drivers.type / حقل typeCar).
class VehicleTypeOption {
  const VehicleTypeOption(this.value, this.labelAr);
  final String value;
  final String labelAr;
}

const kVehicleTypeOptions = <VehicleTypeOption>[
  VehicleTypeOption('car', 'سيارة'),
  VehicleTypeOption('van_large', 'فان كبير'),
  VehicleTypeOption('van_small', 'فان صغير'),
];

String vehicleTypeLabelAr(String? raw) {
  final t = raw?.trim() ?? '';
  for (final o in kVehicleTypeOptions) {
    if (o.value == t) return o.labelAr;
  }
  if (t == 'motorcycle') return 'دراجة';
  return t;
}

String normalizeVehicleTypeValue(String? raw) {
  final t = raw?.trim() ?? '';
  for (final o in kVehicleTypeOptions) {
    if (o.value == t) return o.value;
  }
  return 'car';
}
