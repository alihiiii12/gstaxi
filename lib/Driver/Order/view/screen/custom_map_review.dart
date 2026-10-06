import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/maps/google_map_helpers.dart';

class CustomerMapPreview extends StatefulWidget {
  @override
  State<CustomerMapPreview> createState() => _CustomerMapPreviewState();
}

class _CustomerMapPreviewState extends State<CustomerMapPreview> {
  final ll.LatLng customerLocation = const ll.LatLng(33.5138, 36.2765);

  final Map<String, dynamic> orderData = {
    'customer_name': 'رنا الجاسم',
    'distance_to_client': '1.2 كم (3 دقائق)',
    'pickup_address': 'دمشق - المزة - جبل - شارع الجلاء',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'معاينة موقع الزبون',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: googleLatLngFrom(customerLocation),
              zoom: 15,
            ),
            markers: {
              gmapsMarker(
                id: 'customer',
                point: customerLocation,
                icon: MapMarkerIcons.passenger,
              ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildCustomerDetailsCard(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.blue[50],
                  child: Icon(Icons.person, size: 30, color: Colors.blue[900]),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderData['customer_name'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'يبعد عنك: ${orderData['distance_to_client']}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildActionIcon(Icons.phone, Colors.green, 'اتصال'),
              ],
            ),
            const Divider(height: 30),
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.grey[400]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    orderData['pickup_address'],
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'العودة لقبول الطلب',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, Color color, String label) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
