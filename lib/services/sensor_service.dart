import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Thin wrappers around the device GPS and magnetometer, used to auto-fill
/// shooting conditions (latitude, altitude, firing azimuth).
///
/// Every failure mode — plugin unsupported (web on desktop), location service
/// off, permission denied, sensor absent — degrades to `null` so the UI can
/// show a friendly hint and keep manual entry working. Nothing here throws.
class GpsFix {
  final double latitudeDeg;
  final double longitudeDeg;
  final double? altitudeM;

  const GpsFix({
    required this.latitudeDeg,
    required this.longitudeDeg,
    this.altitudeM,
  });
}

class SensorService {
  SensorService._();

  /// Current device position, requesting permission when needed.
  /// Returns null when location is unavailable for any reason.
  static Future<GpsFix?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return GpsFix(
        latitudeDeg: pos.latitude,
        longitudeDeg: pos.longitude,
        altitudeM: pos.altitude,
      );
    } catch (_) {
      return null;
    }
  }

  /// One compass heading reading (degrees clockwise from magnetic north),
  /// or null when the device/browser has no compass or it stays silent for
  /// 3s. Returns the first non-null heading from the sensor stream.
  static Future<double?> readHeading() async {
    try {
      final events = FlutterCompass.events;
      if (events == null) return null;
      // Some browsers expose the stream but never emit (no permission or no
      // sensor) — a silent wait would spin the UI button forever.
      await for (final e in events.timeout(const Duration(seconds: 3),
          onTimeout: (sink) => sink.close())) {
        final h = e.heading;
        if (h != null && !h.isNaN) return h;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
