import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../Customer/view/widgets/customer_ui_theme.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/services/account_deletion_service.dart';
import '../../../Auth/auth_session.dart';
import '../../../Home/view/widgets/driver_screen_shell.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await http.get(
      Uri.parse(ApiEndpoints.driverMeProfile),
      headers: await ApiEndpoints.headers(),
    );
    final map = json.decode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || map['success'] != true) {
      throw Exception(map['message'] ?? res.body);
    }
    return Map<String, dynamic>.from(map['data'] as Map);
  }

  Future<void> _logout() async {
    await AuthSession.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return DriverScreenShell(
      title: 'الملف الشخصي',
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: CustomerUiTheme.navy),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CustomerUiTheme.navy),
                  ),
                ),
              );
            }
            final d = snap.data!;
            final user = d['user'] is Map
                ? Map<String, dynamic>.from(d['user'] as Map)
                : <String, dynamic>{};
            final trans = d['transType'] is Map
                ? Map<String, dynamic>.from(d['transType'] as Map)
                : <String, dynamic>{};
            final fn = user['firstName']?.toString() ?? '';
            final ln = user['lastName']?.toString() ?? '';
            final name =
                ('$fn $ln').trim().isEmpty ? 'الفارس' : ('$fn $ln').trim();
            final phone = user['number']?.toString() ?? '';
            final plate = d['carNumber']?.toString() ?? '';
            final carTypeName = trans['name']?.toString() ?? '';
            final driverPhotoUrl = d['driver_photo_url']?.toString();

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                children: [
                  _buildHeader(name: name, driverPhotoUrl: driverPhotoUrl),
                  const SizedBox(height: 24),
                  _buildInfoSection(
                    title: 'المعلومات الشخصية',
                    items: [
                      _buildInfoTile(Icons.person_rounded, 'الاسم الكامل', name),
                      _buildInfoTile(
                        Icons.phone_android_rounded,
                        'رقم الموبايل',
                        phone.isEmpty ? '—' : phone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoSection(
                    title: 'بيانات المركبة',
                    items: [
                      _buildInfoTile(
                        Icons.local_taxi_rounded,
                        'فئة السيارة',
                        carTypeName.isEmpty ? '—' : carTypeName,
                      ),
                      _buildInfoTile(
                        Icons.tag_rounded,
                        'رقم اللوحة',
                        plate.isEmpty ? '—' : plate,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoSection(
                    title: 'الحساب والأمان',
                    items: [
                      _buildActionTile(
                        Icons.privacy_tip_outlined,
                        'سياسة الخصوصية',
                        AccountDeletionService.openPrivacyPolicy,
                      ),
                      _buildActionTile(
                        Icons.delete_forever_rounded,
                        'حذف الحساب',
                        () => AccountDeletionService.confirmAndDeleteAccount(
                          context,
                        ),
                        isDelete: true,
                      ),
                      _buildActionTile(
                        Icons.logout_rounded,
                        'تسجيل الخروج',
                        _logout,
                        isDelete: true,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader({
    required String name,
    String? driverPhotoUrl,
  }) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CustomerUiTheme.navy.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 52,
                backgroundColor: CustomerUiTheme.navy,
                backgroundImage:
                    (driverPhotoUrl != null && driverPhotoUrl.isNotEmpty)
                        ? NetworkImage(driverPhotoUrl)
                        : null,
                child: (driverPhotoUrl == null || driverPhotoUrl.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white, size: 44)
                    : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          name,
          style: const TextStyle(
            color: CustomerUiTheme.navy,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: CustomerUiTheme.amber.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'حساب الفارس',
            style: TextStyle(
              color: CustomerUiTheme.navy,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> items,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: CustomerUiTheme.navy,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            decoration: CustomerUiTheme.glassCard(radius: 20),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: CustomerUiTheme.navy),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: CustomerUiTheme.muted.withValues(alpha: 0.9),
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: CustomerUiTheme.navy,
        ),
      ),
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDelete = false,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: isDelete ? const Color(0xFFDC2626) : CustomerUiTheme.navy,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: isDelete ? const Color(0xFFB91C1C) : CustomerUiTheme.navy,
        ),
      ),
    );
  }
}
