import 'dart:convert';

/// A single recorded shot / shooting-session entry. Mirrors Ballistic's
/// "Target Log / Log Book" — records environmental conditions, point of
/// impact, group size, and notes for post-range analysis.
class TargetLogEntry {
  final String id;
  final DateTime timestamp;
  final String firearmId;
  final String cartridgeId;
  final String bulletId;

  // Environment at the time of the shot
  final double temperatureC;
  final double pressureHpa;
  final double humidity;
  final double altitudeM;
  final double windSpeedMph;
  final double windDirDeg;

  // Shot result
  final double rangeYd;
  final double dropIn; // actual measured drop, inches (+ = high)
  final double windageIn; // actual measured windage, inches (+ = right)
  final double groupSizeMoA; // extreme spread, MOA
  final bool coldBarrel; // first shot from clean/cold bore
  final String? notes;

  final double pressureHpa;

  const TargetLogEntry({
    required this.id,
    required this.timestamp,
    required this.firearmId,
    required this.cartridgeId,
    required this.bulletId,
    required this.temperatureC,
    required this.pressureHpa,
    required this.humidity,
    required this.altitudeM,
    required this.windSpeedMph,
    required this.windDirDeg,
    required this.rangeYd,
    required this.dropIn,
    required this.windageIn,
    required this.groupSizeMoA,
    required this.coldBarrel,
    this.notes,
  });

  factory TargetLogEntry.create({
    required String firearmId,
    required String cartridgeId,
    required String bulletId,
    required double temperatureC,
    required double pressureHpa,
    required double humidity,
    required double altitudeM,
    required double windSpeedMph,
    required double windDirDeg,
    required double rangeYd,
    required double dropIn,
    required double windageIn,
    required double groupSizeMoA,
    required bool coldBarrel,
    String? notes,
  }) =>
      TargetLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        firearmId: firearmId,
        cartridgeId: cartridgeId,
        bulletId: bulletId,
        temperatureC: temperatureC,
        pressureHpa: pressureHpa,
        humidity: humidity,
        altitudeM: altitudeM,
        windSpeedMph: windSpeedMph,
        windDirDeg: windDirDeg,
        rangeYd: rangeYd,
        dropIn: dropIn,
        windageIn: windageIn,
        groupSizeMoA: groupSizeMoA,
        coldBarrel: coldBarrel,
        notes: notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'firearmId': firearmId,
        'cartridgeId': cartridgeId,
        'bulletId': bulletId,
        'temperatureC': temperatureC,
        'pressureHpa': pressureHpa,
        'humidity': humidity,
        'altitudeM': altitudeM,
        'windSpeedMph': windSpeedMph,
        'windDirDeg': windDirDeg,
        'rangeYd': rangeYd,
        'dropIn': dropIn,
        'windageIn': windageIn,
        'groupSizeMoA': groupSizeMoA,
        'coldBarrel': coldBarrel,
        if (notes != null) 'notes': notes,
      };

  factory TargetLogEntry.fromJson(Map<String, dynamic> j) => TargetLogEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        firearmId: j['firearmId'] as String,
        cartridgeId: j['cartridgeId'] as String,
        bulletId: j['bulletId'] as String,
        temperatureC: (j['temperatureC'] as num).toDouble(),
        pressureHpa: (j['pressureHpa'] as num).toDouble(),
        humidity: (j['humidity'] as num).toDouble(),
        altitudeM: (j['altitudeM'] as num).toDouble(),
        windSpeedMph: (j['windSpeedMph'] as num).toDouble(),
        windDirDeg: (j['windDirDeg'] as num).toDouble(),
        rangeYd: (j['rangeYd'] as num).toDouble(),
        dropIn: (j['dropIn'] as num).toDouble(),
        windageIn: (j['windageIn'] as num).toDouble(),
        groupSizeMoA: (j['groupSizeMoA'] as num?)?.toDouble() ?? 0,
        coldBarrel: (j['coldBarrel'] as bool?) ?? false,
        notes: j['notes'] as String?,
      );
}
