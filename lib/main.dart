import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vehicle_tracking_system/online_pulsator.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://bcuzcgnlxwxbiverlwsi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjdXpjZ25seHd4Yml2ZXJsd3NpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc0OTU1MzIsImV4cCI6MjA2MzA3MTUzMn0.ld2NCqiygZ8CSDNDhvWP5_5MoHyEL-2obo1Z7XSZEpA',
  );
  runApp(GetMaterialApp(
    debugShowCheckedModeBanner: false,
    home: TrackingHomePage(),
    theme: ThemeData.dark(),
  ));
}

class GeoPointWithSpeed extends GeoPoint {
  final num speed;
  final num? course;

  GeoPointWithSpeed({
    required super.latitude,
    required super.longitude,
    required this.speed,
    this.course,
  });

  GeoPointWithSpeed.fromGeoPoint(GeoPoint point, this.speed, {this.course})
      : super(latitude: point.latitude, longitude: point.longitude);
}

class TrackingController extends GetxController {
  final SupabaseClient supabase = Supabase.instance.client;
  final mapController = MapController.customLayer(
    customTile: CustomTile(
      sourceName: "dark_tile",
      tileExtension: ".png",
      minZoomLevel: 2,
      maxZoomLevel: 20,
      urlsServers: [
        TileURLs(
          url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
          subdomains: ['a', 'b', 'c', 'd'],
        )
      ],
    ),
    initMapWithUserPosition: UserTrackingOption(enableTracking: false),
  );

  final vehicleId = "f0fd260d8e8646e8a7c2954b3c1d2fa2";
  final latestGeoPoint = Rxn<GeoPoint>();
  final trackingData = Rxn<Map<String, dynamic>>();
  final address = RxnString();
  final historicalPoints = <GeoPoint>[].obs;
  final selectedDuration = RxString('12 hours');
  final durationOptions = {
    '1 hour': const Duration(hours: 1),
    '6 hours': const Duration(hours: 6),
    '12 hours': const Duration(hours: 12),
    '1 day': const Duration(days: 1),
    '1 week': const Duration(days: 7),
  };

  final List<String> roadIds = [];
  GeoPoint? _lastEndMarker;
  bool _initialMapUpdated = false;

  @override
  void onInit() {
    super.onInit();
    fetchHistoricalData().then((_) {
      _initialMapUpdated = true;
    });
    listenToTracking();
  }

  void listenToTracking() {
    try {
      supabase
          .from('TrackingData')
          .stream(primaryKey: ['id'])
          .eq('vehicleId', vehicleId)
          .order('timestamp', ascending: false)
          .limit(1)
          .listen((event) {
            if (event.isNotEmpty) {
              updateTracking(event.first);
            }
          });
    } catch (e) {
      Get.snackbar('Error', 'An error occurred while connecting to tracker');
    }
  }

  Future<void> fetchHistoricalData() async {
    final duration = durationOptions[selectedDuration.value]!;
    final cutoffTime = DateTime.now().subtract(duration);

    final response = await supabase
        .from('TrackingData')
        .select()
        .eq('vehicleId', vehicleId)
        .gte('timestamp', cutoffTime.toIso8601String())
        .order('timestamp', ascending: true);
    Logger().d(response);

    if (response.isNotEmpty) {
      historicalPoints.value = response
          .map((point) => GeoPointWithSpeed(
                latitude: point['latitude'],
                longitude: point['longitude'],
                speed: point['speedInKmph']?.toDouble() ?? 0.0,
                course: point['courseDegree']?.toDouble(),
              ))
          .toList();

      await drawFullHistory();
    }
  }

  Future<void> drawFullHistory() async {
    // Clear roads
    for (final id in roadIds) {
      await mapController.removeRoad(roadKey: id);
    }
    roadIds.clear();
    await mapController.removeMarkers(historicalPoints);

    if (historicalPoints.length < 2) return;

    await mapController.drawRoad(
      historicalPoints.first,
      historicalPoints.last,
      intersectPoint: historicalPoints.sublist(1, historicalPoints.length - 1),
      roadOption: RoadOption(
        roadColor: Colors.cyanAccent,
        roadWidth: 10,
        roadBorderColor: Colors.black,
        zoomInto: true,
      ),
    );

    final parkedPoints = historicalPoints
        .where((p) => (p as GeoPointWithSpeed).speed < 1.0)
        .where((p) => p != historicalPoints.last)
        .toList();

    for (final point in parkedPoints) {
      final offsetParkingPoint = GeoPoint(
        latitude: point.latitude + 0.00001,
        longitude: point.longitude + 0.00001,
      );

      await mapController.addMarker(
        offsetParkingPoint,
        markerIcon: MarkerIcon(
          icon: Icon(Icons.local_parking, color: Colors.orange, size: 48),
        ),
      );
    }

    await _addStartAndEndMarkers();
  }

  Future<void> drawLatestSegment() async {
    if (historicalPoints.length < 2) return;

    final lastTwo = historicalPoints.sublist(historicalPoints.length - 2);

    // Draw road segment from the previous point to the new one
    await mapController.drawRoad(
      lastTwo[0],
      lastTwo[1],
      roadOption: RoadOption(
        roadColor: Colors.cyanAccent,
        roadWidth: 10,
        roadBorderColor: Colors.black,
        zoomInto: false,
      ),
    );

    // Add parked marker if speed is low
    final lastPoint = lastTwo.last as GeoPointWithSpeed;
    // Add parking marker if speed is low
    if (lastPoint.speed < 1.0) {
      // Offset the parking marker slightly to avoid overlapping with the end marker
      final offsetParkingPoint = GeoPoint(
        latitude: lastPoint.latitude + 0.00001,
        longitude: lastPoint.longitude + 0.00001,
      );

      await mapController.addMarker(
        offsetParkingPoint,
        markerIcon: MarkerIcon(
          icon: Icon(Icons.local_parking, color: Colors.orange, size: 48),
        ),
      );
    }

    // Handle end marker update
    final newEndMarker = historicalPoints.last;
    if (_lastEndMarker == null ||
        _lastEndMarker!.latitude != newEndMarker.latitude ||
        _lastEndMarker!.longitude != newEndMarker.longitude) {
      if (_lastEndMarker != null) {
        await mapController.removeMarker(_lastEndMarker!);
      }
      await mapController.addMarker(
        newEndMarker,
        markerIcon: MarkerIcon(
          iconWidget: OnlinePulsator(),
        ),
      );
      _lastEndMarker = newEndMarker;
    }
  }

  Future<void> _addStartAndEndMarkers() async {
    await mapController.addMarker(
      historicalPoints.first,
      markerIcon: MarkerIcon(
        icon: Icon(Icons.start, color: Colors.green, size: 48),
      ),
    );

    if (_lastEndMarker != null) {
      await mapController.removeMarker(_lastEndMarker!);
    }

    final newEnd = historicalPoints.last;
    await mapController.addMarker(
      newEnd,
      markerIcon: MarkerIcon(
        iconWidget: OnlinePulsator(),
      ),
    );
    _lastEndMarker = newEnd;
  }

  Future<void> updateTracking(Map<String, dynamic> data) async {
    trackingData.value = data;
    final point = GeoPoint(
      latitude: data['latitude'],
      longitude: data['longitude'],
    );
    latestGeoPoint.value = point;
    final newPoint = GeoPointWithSpeed.fromGeoPoint(point, data['speedInKmph'],
        course: data['courseDegree']);

    final isNewPoint = historicalPoints.isEmpty ||
        historicalPoints.last.latitude != newPoint.latitude ||
        historicalPoints.last.longitude != newPoint.longitude;

    if (isNewPoint) {
      historicalPoints.add(newPoint);
      await mapController.setZoom(zoomLevel: 16);
      getAddressFromLatLng(point);
      await drawLatestSegment();
    } else if (!_initialMapUpdated) {
      await mapController.setZoom(zoomLevel: 16);
      getAddressFromLatLng(point);
      await drawFullHistory();
      _initialMapUpdated = true;
    }
  }

  Future<void> getAddressFromLatLng(GeoPoint point) async {
    final url =
        'https://geocode.maps.co/reverse?lat=${point.latitude}&lon=${point.longitude}&api_key=6829c400938a8716679384gtw457c64';
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      address.value = data['display_name'];
    }
  }

  void updateDuration(String? duration) {
    if (duration != null) {
      selectedDuration.value = duration;
      fetchHistoricalData();
    }
  }
}

class TrackingHomePage extends StatelessWidget {
  final controller = Get.put(TrackingController());

  TrackingHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🚀 GPS Tracker'),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Obx(
                () => DropdownButton<String>(
                  value: controller.selectedDuration.value,
                  dropdownColor: Colors.black87,
                  onChanged: controller.updateDuration,
                  items: controller.durationOptions.keys
                      .map((String duration) => DropdownMenuItem<String>(
                            value: duration,
                            child: Text(duration),
                          ))
                      .toList(),
                ),
              )),
        ],
      ),
      body: Obx(() => Stack(
            children: [
              OSMFlutter(
                controller: controller.mapController,
                osmOption: OSMOption(
                  zoomOption: ZoomOption(
                    initZoom: 14,
                    minZoomLevel: 8,
                    maxZoomLevel: 19,
                    stepZoom: 1.0,
                  ),
                  showZoomController: true,
                ),
              ),
              if (controller.trackingData.value != null)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent, width: 1.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDataColumn(
                            "💨",
                            "Speed",
                            "${controller.trackingData.value!["speedInKmph"] ?? 'N/A'} km/h",
                            context),
                        _buildDataColumn(
                            "🧭",
                            "Course",
                            "${controller.trackingData.value!["courseDegree"] ?? 'N/A'}°",
                            context),
                        _buildDataColumn(
                            "🛰️",
                            "Satellites",
                            "${controller.trackingData.value!["numberOfSatellitesUsed"] ?? 'N/A'}",
                            context),
                        _buildDataColumn(
                            "⛰️",
                            "Altitude",
                            "${controller.trackingData.value!["altitudeInMeters"] ?? 'N/A'} m",
                            context),
                        Obx(() => _buildDataColumn(
                            "📍",
                            "Location",
                            controller.address.value ?? "Locating...",
                            context)),
                      ],
                    ),
                  ),
                ),
            ],
          )),
    );
  }

  Widget _buildDataColumn(
      String icon, String label, String value, BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Text(icon, style: TextStyle(fontSize: 20)),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white60, fontSize: 12)),
          SizedBox(width: 16),
        ]),
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.4,
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
      ],
    );
  }
}
