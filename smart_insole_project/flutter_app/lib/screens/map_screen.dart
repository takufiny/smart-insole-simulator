// ============================================================
// MapScreen — Live GPS route map using google_maps_flutter
// ============================================================
// SETUP NOTES:
//   1. Enable "Maps SDK for Android/iOS" in Google Cloud Console
//   2. Add your API key to AndroidManifest.xml and AppDelegate.swift
//      <meta-data android:name="com.google.android.geo.API_KEY"
//                 android:value="YOUR_KEY"/>
//   3. Add location permissions in AndroidManifest.xml + Info.plist
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../models/insole_data.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines  = {};
  final List<LatLng>  _routePoints = [];
  Marker?             _currentMarker;
  bool                _followRunner = true;

  @override
  void initState() {
    super.initState();
    // Subscribe to BLE stream to update route in real-time
    final ble = context.read<BleService>();
    ble.dataStream.listen(_onNewData);

    // Seed with existing history
    for (final frame in ble.history.frames) {
      _addPoint(frame);
    }
  }

  void _onNewData(InsoleData d) {
    if (d.latitude == 0.0 && d.longitude == 0.0) return;
    if (mounted) setState(() => _addPoint(d));
  }

  void _addPoint(InsoleData d) {
    if (d.latitude == 0.0) return;
    final pt = LatLng(d.latitude, d.longitude);
    _routePoints.add(pt);
    _polylines
      ..clear()
      ..add(Polyline(
        polylineId: const PolylineId('route'),
        points: List.from(_routePoints),
        color: const Color(0xFF00C86F),
        width: 4,
        geodesic: true,
      ));

    _currentMarker = Marker(
      markerId: const MarkerId('runner'),
      position: pt,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: const InfoWindow(title: 'Runner'),
    );

    if (_followRunner && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(pt));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble  = context.watch<BleService>();
    final data = ble.latestData;

    final initialTarget = (_routePoints.isNotEmpty)
        ? _routePoints.last
        : const LatLng(13.7563, 100.5018); // Bangkok default

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text('GPS Route', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_followRunner ? Icons.my_location : Icons.location_disabled,
                color: _followRunner ? const Color(0xFF00C86F) : Colors.grey),
            tooltip: 'Follow runner',
            onPressed: () => setState(() => _followRunner = !_followRunner),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Google Map ───────────────────────────────────
          GoogleMap(
            onMapCreated: (c) => _mapController = c,
            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 16),
            polylines: _polylines,
            markers: {if (_currentMarker != null) _currentMarker!},
            mapType: MapType.normal,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onTap: (_) => setState(() => _followRunner = false),
          ),

          // ── Live Metrics Overlay ────────────────────────
          if (data != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xDD0D1117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(Icons.route,       '${data.distanceKm.toStringAsFixed(2)} km', 'Distance'),
                    _divider(),
                    _stat(Icons.speed,        data.paceFormatted,                        'Pace'),
                    _divider(),
                    _stat(Icons.directions_run,'${data.speedKmh.toStringAsFixed(1)} km/h','Speed'),
                    _divider(),
                    _stat(Icons.pin_drop,
                        '${_routePoints.length} pts', 'GPS points'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: const Color(0xFF00C86F), size: 18),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white,
          fontWeight: FontWeight.bold, fontSize: 13)),
      Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
    ],
  );

  Widget _divider() => Container(height: 32, width: 1, color: Colors.white12);
}
