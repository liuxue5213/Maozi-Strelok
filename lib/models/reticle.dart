import 'dart:ui';

/// A real-world rifle-scope reticle, described as a set of geometric elements
/// (lines, dots, ticks, posts, circles) measured in reticle angular units
/// (MIL or MOA) relative to the optical center. This declarative form lets one
/// painter render any reticle in the library faithfully, matching Strelok's
/// "reticle library" feature.
///
/// Coordinate convention (same as the solver / painter):
///   origin = optical center; +x = right; +y = DOWN (screen down = bullet low).
/// All positions/sizes are in the reticle's native angular unit unless noted.
class ReticleSpec {
  final String id;
  final String name;
  final String manufacturer;
  /// 'MIL' or 'MOA' — the unit the geometry is expressed in.
  final String unit;
  /// Half-width of the drawn field, in [unit] (the painter covers ±fieldHalf).
  final double fieldHalf;
  /// Focal plane: 'FFP' (reticle scales with zoom) or 'SFP' (fixed at a
  /// reference magnification, requires [sfpRefMag] to convert).
  final String focalPlane;
  /// For SFP reticles, the magnification at which the geometry is true.
  final double sfpRefMag;
  final List<ReticleLine> lines;
  final List<ReticleDot> dots;
  final List<ReticleTick> ticks;
  final List<ReticlePost> posts;
  final List<ReticleCircle> circles;
  /// Optional descriptive note (e.g. "USMC mil-dot, 0.85 mil spacing").
  final String? notes;

  const ReticleSpec({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.unit,
    this.fieldHalf = 10,
    this.focalPlane = 'FFP',
    this.sfpRefMag = 1,
    this.lines = const [],
    this.dots = const [],
    this.ticks = const [],
    this.posts = const [],
    this.circles = const [],
    this.notes,
  });

  factory ReticleSpec.fromJson(Map<String, dynamic> j) => ReticleSpec(
        id: j['id'] as String,
        name: j['name'] as String,
        manufacturer: j['manufacturer'] as String? ?? '',
        unit: j['unit'] as String? ?? 'MIL',
        fieldHalf: (j['fieldHalf'] as num?)?.toDouble() ?? 10,
        focalPlane: j['focalPlane'] as String? ?? 'FFP',
        sfpRefMag: (j['sfpRefMag'] as num?)?.toDouble() ?? 1,
        lines: (j['lines'] as List?)
                ?.map((e) => ReticleLine.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        dots: (j['dots'] as List?)
                ?.map((e) => ReticleDot.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        ticks: (j['ticks'] as List?)
                ?.map((e) => ReticleTick.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        posts: (j['posts'] as List?)
                ?.map((e) => ReticlePost.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        circles: (j['circles'] as List?)
                ?.map((e) => ReticleCircle.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        notes: j['notes'] as String?,
      );
}

/// A straight line from (x1,y1) to (x2,y2), all in reticle units. Optional
/// [width] (in px at the reference scale) and [dashed].
class ReticleLine {
  final double x1, y1, x2, y2;
  final double width;
  final bool dashed;
  const ReticleLine(this.x1, this.y1, this.x2, this.y2,
      {this.width = 1.0, this.dashed = false});
  factory ReticleLine.fromJson(Map<String, dynamic> j) => ReticleLine(
        (j['x1'] as num).toDouble(),
        (j['y1'] as num).toDouble(),
        (j['x2'] as num).toDouble(),
        (j['y2'] as num).toDouble(),
        width: (j['width'] as num?)?.toDouble() ?? 1.0,
        dashed: (j['dashed'] as bool?) ?? false,
      );
}

/// A filled dot at (x,y) with a given radius (reticle units).
class ReticleDot {
  final double x, y, r;
  const ReticleDot(this.x, this.y, this.r);
  factory ReticleDot.fromJson(Map<String, dynamic> j) => ReticleDot(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['r'] as num?)?.toDouble() ?? 0.15,
      );
}

/// A tick mark: a short line crossing an axis at position [pos] along [axis]
/// ('h' = horizontal axis tick, 'v' = vertical axis tick), of half-length
/// [halfLen] (perpendicular to the axis). Used for BDC / ranging stadia.
class ReticleTick {
  final String axis; // 'h' (on horizontal line) or 'v' (on vertical line)
  final double pos; // position along the axis (reticle units from center)
  final double halfLen; // half length perpendicular to the axis
  final double width;
  const ReticleTick(this.axis, this.pos, this.halfLen, {this.width = 1.0});
  factory ReticleTick.fromJson(Map<String, dynamic> j) => ReticleTick(
        j['axis'] as String? ?? 'v',
        (j['pos'] as num).toDouble(),
        (j['halfLen'] as num?)?.toDouble() ?? 0.5,
        width: (j['width'] as num?)?.toDouble() ?? 1.0,
      );
}

/// A thick post (heavy stadia line) — used on German #4 / duplex reticles.
/// Described like a line but typically wider.
class ReticlePost {
  final double x1, y1, x2, y2;
  final double width;
  const ReticlePost(this.x1, this.y1, this.x2, this.y2, {this.width = 3.0});
  factory ReticlePost.fromJson(Map<String, dynamic> j) => ReticlePost(
        (j['x1'] as num).toDouble(),
        (j['y1'] as num).toDouble(),
        (j['x2'] as num).toDouble(),
        (j['y2'] as num).toDouble(),
        width: (j['width'] as num?)?.toDouble() ?? 3.0,
      );
}

/// A circle (ring) centered at (x,y) with radius [r] (reticle units).
class ReticleCircle {
  final double x, y, r;
  final double width;
  const ReticleCircle(this.x, this.y, this.r, {this.width = 1.0});
  factory ReticleCircle.fromJson(Map<String, dynamic> j) => ReticleCircle(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['r'] as num?)?.toDouble() ?? 1.0,
        width: (j['width'] as num?)?.toDouble() ?? 1.0,
      );
}

/// A parsed reticle + its derived color (for themed painting).
class ReticleRender {
  final ReticleSpec spec;
  final Color color;
  const ReticleRender(this.spec, this.color);
}
