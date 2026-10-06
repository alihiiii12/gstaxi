class UserResponseModel {
  final bool success;
  final String message;
  final DriverData? data;

  UserResponseModel({
    required this.success,
    required this.message,
    this.data,
  });

  factory UserResponseModel.fromJson(Map<String, dynamic> json) {
    DriverData? data;
    try {
      final userRaw = json['user'] ?? json['data'];
      if (userRaw is Map) {
        final userMap = Map<String, dynamic>.from(userRaw);
        if (json['token'] != null) {
          userMap['token'] = json['token'];
        }
        data = DriverData.fromJson(userMap);
      }
    } catch (_) {
      data = null;
    }
    return UserResponseModel(
      success: json['state'] == true ||
          json['success'] == true ||
          json['success']?.toString().toLowerCase() == 'true',
      message: json['message']?.toString() ?? '',
      data: data,
    );
  }
}

class DriverData {
  final int id;
  final String firstName;
  final String lastName;
  final String number;
  final String carNumber;
  final String typeCar;
  final String status;
  final String token;
  final String roll;
  final bool changePasswordNeeded;
  final int? driverId;
  final int? transTypeId;
  /// صلاحيات الموظف (لوحة الإدارة فقط)
  final List<String> permissions;

  DriverData({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.number,
    required this.carNumber,
    required this.typeCar,
    this.status = "active",
    required this.token,
    required this.roll,
    required this.changePasswordNeeded,
    this.driverId,
    this.transTypeId,
    this.permissions = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'number': number,
      'carNumber': carNumber,
      'typeCar': typeCar,
      'status': status,
      'token': token,
      'roll': roll,
      'changePasswordNeeded': changePasswordNeeded,
      'driverId': driverId,
      'transTypeId': transTypeId,
      'permissions': permissions,
    };
  }

  factory DriverData.fromJson(Map<String, dynamic> json) {
    return DriverData(
      id: _asInt(json['id']),
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      carNumber: json['carNumber']?.toString() ?? '',
      typeCar: (json['typeCar'] ?? json['cartype'])?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      token: json['token']?.toString() ?? '',
      roll: json['roll']?.toString() ?? '',
      changePasswordNeeded: _asBool(
        json['changePasswordNeeded'] ?? json['ChangePasswordNeeded'],
      ),
      driverId: json['driverId'] != null
          ? int.tryParse(json['driverId'].toString())
          : null,
      transTypeId: json['transTypeId'] != null
          ? int.tryParse(json['transTypeId'].toString())
          : null,
      permissions: _asStringList(json['permissions']),
    );
  }
}

List<String> _asStringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList();
  }
  if (v is Map) {
    return v.values.map((e) => e.toString()).toList();
  }
  return const [];
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase().trim();
  return s == 'true' || s == '1' || s == 'yes';
}
