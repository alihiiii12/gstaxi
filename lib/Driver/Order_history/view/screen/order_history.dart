import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/request_category_fare_display.dart';
import '../../../Home/view/widgets/driver_screen_shell.dart';
import '../../../../Customer/view/widgets/customer_ui_theme.dart';
import '../../controller/trips_history_controller.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TripsHistoryController c = Get.put(TripsHistoryController());

    return DriverScreenShell(
      title: 'سجل الرحلات',
      actions: [
        DriverHeaderIconButton(
          icon: Icons.refresh_rounded,
          onTap: () => c.load(),
        ),
      ],
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Obx(() {
          if (c.loading.value) {
            return const Center(
              child: CircularProgressIndicator(
                color: CustomerUiTheme.navy,
              ),
            );
          }
          if (c.error.value.isNotEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  c.error.value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CustomerUiTheme.navy),
                ),
              ),
            );
          }
          if (c.trips.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: CustomerUiTheme.glassCard(radius: 24),
                  child: const Text(
                    'لا توجد رحلات مسجّلة بعد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CustomerUiTheme.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            );
          }

          final app = c.appTrips;
          final free = c.freeMeterTrips;

          return DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  child: Container(
                    decoration: CustomerUiTheme.glassCard(radius: 16),
                    child: TabBar(
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      labelColor: CustomerUiTheme.navy,
                      unselectedLabelColor:
                          CustomerUiTheme.muted.withValues(alpha: 0.85),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      tabs: [
                        Tab(text: 'التطبيق (${app.length})'),
                        Tab(text: 'العداد (${free.length})'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TripList(
                        trips: app,
                        isFree: false,
                        emptyText: 'لا رحلات تطبيق بعد',
                      ),
                      _TripList(
                        trips: free,
                        isFree: true,
                        emptyText: 'لا رحلات عداد بعد',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TripList extends StatelessWidget {
  const _TripList({
    required this.trips,
    required this.isFree,
    required this.emptyText,
  });

  final List<Map<String, dynamic>> trips;
  final bool isFree;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: CustomerUiTheme.glassCard(radius: 20),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CustomerUiTheme.muted.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: trips.length,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TripCard(hist: trips[index], isFree: isFree),
        );
      },
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.hist, required this.isFree});

  final Map<String, dynamic> hist;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    final req = hist['request'] as Map<String, dynamic>? ?? {};
    final fareLine = driverRequestUnifiedPricingLine(req);
    final created = hist['created_at'] ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CustomerUiTheme.glassCard(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  created.toString(),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                isFree ? 'عداد حر #${req['id'] ?? ''}' : 'طلب #${req['id'] ?? ''}',
                style: const TextStyle(
                  color: Color(0xFF11215B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 0.5),
          ),
          Text(
            fareLine ??
                (hist['finalCost'] != null
                    ? 'الأجرة: ${hist['finalCost']} ل.س'
                    : 'الأجرة: —'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF11215B),
            ),
          ),
        ],
      ),
    );
  }
}
