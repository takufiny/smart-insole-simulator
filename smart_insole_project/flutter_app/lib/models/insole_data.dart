// ============================================================
// InsoleData — Immutable snapshot of one BLE payload frame
// ============================================================

/// Raw pressure value range from the 12-bit ESP32 ADC.
const int kMaxPressure = 4095;

/// Strike type classified by the pressure analysis engine.
enum StrikeType { heel, midfoot, forefoot, unknown }

/// One decoded BLE notification frame.
class InsoleData {
  // ── Pressure (0–4095 raw ADC) ────────────────────────────
  final int heel;
  final int forefootLeft;
  final int forefootRight;
  final int toe;

  // ── GPS / Running Metrics ────────────────────────────────
  final double paceMinPerKm;  // 0 when stationary
  final double distanceKm;
  final double latitude;
  final double longitude;
  final double speedKmh;

  final DateTime timestamp;

  const InsoleData({
    required this.heel,
    required this.forefootLeft,
    required this.forefootRight,
    required this.toe,
    required this.paceMinPerKm,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.timestamp,
  });

  // ── Factory: parse from JSON map ─────────────────────────
  factory InsoleData.fromJson(Map<String, dynamic> json) {
    return InsoleData(
      heel:          (json['h']  as num?)?.toInt()    ?? 0,
      forefootLeft:  (json['fl'] as num?)?.toInt()    ?? 0,
      forefootRight: (json['fr'] as num?)?.toInt()    ?? 0,
      toe:           (json['t']  as num?)?.toInt()    ?? 0,
      paceMinPerKm:  (json['pace'] as num?)?.toDouble() ?? 0.0,
      distanceKm:    (json['dist'] as num?)?.toDouble() ?? 0.0,
      latitude:      (json['lat']  as num?)?.toDouble() ?? 0.0,
      longitude:     (json['lng']  as num?)?.toDouble() ?? 0.0,
      speedKmh:      (json['spd']  as num?)?.toDouble() ?? 0.0,
      timestamp:     DateTime.now(),
    );
  }

  // ── Normalised pressure [0.0–1.0] per zone ───────────────
  double get heelNorm       => heel       / kMaxPressure;
  double get forefootLNorm  => forefootLeft  / kMaxPressure;
  double get forefootRNorm  => forefootRight / kMaxPressure;
  double get toeNorm        => toe        / kMaxPressure;

  /// Total load across all sensors (sum, not normalised).
  int get totalPressure => heel + forefootLeft + forefootRight + toe;

  /// Dominant strike zone (highest reading wins).
  StrikeType get dominantStrike {
    final max = [heel, forefootLeft, forefootRight, toe].reduce((a, b) => a > b ? a : b);
    if (max < 200) return StrikeType.unknown;
    if (max == heel) return StrikeType.heel;
    if (max == forefootLeft || max == forefootRight) return StrikeType.midfoot;
    return StrikeType.forefoot;
  }

  /// Human-readable pace string, e.g. "5:32 /km" or "---".
  String get paceFormatted {
    if (paceMinPerKm <= 0) return '---';
    final mins = paceMinPerKm.floor();
    final secs = ((paceMinPerKm - mins) * 60).round();
    return "${mins.toString().padLeft(1)}:${secs.toString().padLeft(2, '0')} /km";
  }

  InsoleData copyWith({int? heel, int? forefootLeft, int? forefootRight, int? toe,
      double? paceMinPerKm, double? distanceKm, double? latitude,
      double? longitude, double? speedKmh}) {
    return InsoleData(
      heel:          heel          ?? this.heel,
      forefootLeft:  forefootLeft  ?? this.forefootLeft,
      forefootRight: forefootRight ?? this.forefootRight,
      toe:           toe           ?? this.toe,
      paceMinPerKm:  paceMinPerKm  ?? this.paceMinPerKm,
      distanceKm:    distanceKm    ?? this.distanceKm,
      latitude:      latitude      ?? this.latitude,
      longitude:     longitude     ?? this.longitude,
      speedKmh:      speedKmh      ?? this.speedKmh,
      timestamp:     DateTime.now(),
    );
  }

  @override
  String toString() =>
    'InsoleData(H:$heel FL:$forefootLeft FR:$forefootRight T:$toe '
    'pace:$paceFormatted dist:${distanceKm.toStringAsFixed(2)}km)';
}

/// Sliding window of recent frames for chart history.
class PressureHistory {
  final int maxLength;
  final List<InsoleData> _frames = [];

  PressureHistory({this.maxLength = 200});

  void add(InsoleData data) {
    _frames.add(data);
    if (_frames.length > maxLength) _frames.removeAt(0);
  }

  List<InsoleData> get frames => List.unmodifiable(_frames);
  bool get isEmpty => _frames.isEmpty;
}
