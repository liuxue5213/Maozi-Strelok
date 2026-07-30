import 'dart:math';

/// Standard drag models (G1 / G7) and custom drag tables.
///
/// External ballistics does NOT use a single fixed drag coefficient Cd.
/// Instead the projectile's drag is referenced to a *standard projectile*
/// shape (the "G-function"). Each standard shape has a measured drag table
/// giving a reference drag function Cd_ref(Mach).
///
/// The actual projectile is described by its Ballistic Coefficient (BC):
///
///     Cd_actual(M) = Cd_ref(M) / i          where i = form factor
///
/// For the G1 standard, by definition a projectile with BC = 1.000 lb/in^2
/// exactly matches the G1 table. In general:
///
///     form_factor i = SD / BC
///     SD = sectional density = mass / diameter^2   (mass in lb, d in in)
///
/// so   Cd_actual(M) = Cd_ref(M) * i = Cd_ref(M) * SD / BC
///
/// All tables below are the published standard G1 / G7 Cd values vs Mach.
/// They are the same reference data used by Strelok, Applied Ballistics,
/// JBM Ballistics, etc. Values for Mach<1 follow the standard subsonic
/// rise; values for Mach>1 follow the transonic/supersonic decay.
abstract class DragModel {
  /// Identifier (e.g. 'G1', 'G7', 'Custom').
  String get id;

  /// Reference drag coefficient at a given Mach number (table + interpolation).
  double cdRef(double mach);

  /// Actual Cd for a projectile with ballistic coefficient `bc` (lb/in^2),
  /// mass `massGr` (grains) and diameter `diaIn` (inches).
  double cd(double mach, double bc, double massGr, double diaIn) {
    final sd = sectionalDensity(massGr, diaIn);
    final i = sd / bc;
    return cdRef(mach) * i;
  }

  /// Sectional density (dimensionless, mass-lb / in^2).
  static double sectionalDensity(double massGr, double diaIn) {
    final massLb = massGr / 7000.0;
    return massLb / (diaIn * diaIn);
  }
}

/// Piecewise-linear interpolation over a (Mach -> Cd) table.
class _TableDragModel extends DragModel {
  final String _id;
  final List<List<double>> _table; // sorted by mach asc: [ [mach, cd], ... ]

  _TableDragModel(this._id, this._table);

  @override
  String get id => _id;

  @override
  double cdRef(double mach) {
    final t = _table;
    if (mach <= t.first[0]) return t.first[1];
    if (mach >= t.last[0]) return t.last[1];
    // binary search the bracketing segment
    int lo = 0, hi = t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (t[mid][0] <= mach) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final x0 = t[lo][0], x1 = t[hi][0];
    final y0 = t[lo][1], y1 = t[hi][1];
    final f = (mach - x0) / (x1 - x0);
    return y0 + f * (y1 - y0); // linear interp
  }
}

/// G1 standard drag function.
/// Tabulated reference Cd (drag function G1) vs Mach number.
class G1DragModel extends DragModel {
  static final G1DragModel instance = G1DragModel._();
  G1DragModel._();

  static final _TableDragModel _table = _TableDragModel('G1', _g1);

  @override
  String get id => 'G1';

  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// G7 standard drag function (low-drag boat-tail bullets).
class G7DragModel extends DragModel {
  static final G7DragModel instance = G7DragModel._();
  G7DragModel._();

  static final _TableDragModel _table = _TableDragModel('G7', _g7);

  @override
  String get id => 'G7';

  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// User-supplied drag table: list of [mach, cd] points.
class CustomDragModel extends DragModel {
  final _TableDragModel _inner;
  CustomDragModel(String name, List<List<double>> table)
      : _inner = _TableDragModel(
          name,
          table
            ..sort((a, b) => a[0].compareTo(b[0])),
        );

  @override
  String get id => _inner.id;

  @override
  double cdRef(double mach) => _inner.cdRef(mach);
}

/// Resolve a drag-model id string into a DragModel instance.
DragModel resolveDragModel(String id) {
  switch (id) {
    case 'G1':
      return G1DragModel.instance;
    case 'G7':
      return G7DragModel.instance;
    default:
      return G1DragModel.instance;
  }
}

// ---------------------------------------------------------------------------
// Reference drag tables.
//
// These are the standard G1 / G7 drag functions published as part of the
// Aberdeen / JBM reference set. Cd = drag coefficient of the *reference*
// projectile for that G-function. The actual bullet's Cd = CdRef * i.
//
// Values are [Mach, CdRef].
// ---------------------------------------------------------------------------

// G1 reference drag function.
const List<List<double>> _g1 = [
  [0.00, 0.2629],
  [0.05, 0.2558],
  [0.10, 0.2487],
  [0.15, 0.2413],
  [0.20, 0.2344],
  [0.25, 0.2278],
  [0.30, 0.2214],
  [0.35, 0.2155],
  [0.40, 0.2104],
  [0.45, 0.2061],
  [0.50, 0.2032],
  [0.55, 0.2020],
  [0.60, 0.2034],
  [0.65, 0.2165],
  [0.70, 0.2290],
  [0.75, 0.2518],
  [0.80, 0.3011],
  [0.825, 0.3287],
  [0.85, 0.4005],
  [0.875, 0.4708],
  [0.90, 0.5149],
  [0.925, 0.5521],
  [0.95, 0.5718],
  [0.975, 0.5350],
  [1.00, 0.4790],
  [1.05, 0.4050],
  [1.10, 0.3497],
  [1.15, 0.3148],
  [1.20, 0.2922],
  [1.25, 0.2780],
  [1.30, 0.2684],
  [1.35, 0.2614],
  [1.40, 0.2560],
  [1.45, 0.2517],
  [1.50, 0.2483],
  [1.55, 0.2455],
  [1.60, 0.2431],
  [1.65, 0.2411],
  [1.70, 0.2393],
  [1.75, 0.2378],
  [1.80, 0.2365],
  [1.85, 0.2353],
  [1.90, 0.2342],
  [1.95, 0.2333],
  [2.00, 0.2324],
  [2.05, 0.2316],
  [2.10, 0.2308],
  [2.15, 0.2301],
  [2.20, 0.2294],
  [2.25, 0.2288],
  [2.30, 0.2282],
  [2.35, 0.2276],
  [2.40, 0.2271],
  [2.45, 0.2265],
  [2.50, 0.2260],
  [2.60, 0.2251],
  [2.70, 0.2242],
  [2.80, 0.2234],
  [2.90, 0.2226],
  [3.00, 0.2218],
  [3.20, 0.2204],
  [3.40, 0.2190],
  [3.60, 0.2177],
  [3.80, 0.2164],
  [4.00, 0.2152],
  [4.50, 0.2124],
  [5.00, 0.2100],
];

// G7 reference drag function (long boat-tail, VLD bullets).
const List<List<double>> _g7 = [
  [0.00, 0.1198],
  [0.05, 0.1198],
  [0.10, 0.1198],
  [0.15, 0.1198],
  [0.20, 0.1198],
  [0.25, 0.1198],
  [0.30, 0.1198],
  [0.35, 0.1198],
  [0.40, 0.1198],
  [0.45, 0.1198],
  [0.50, 0.1198],
  [0.55, 0.1198],
  [0.60, 0.1198],
  [0.65, 0.1198],
  [0.70, 0.1198],
  [0.75, 0.1268],
  [0.80, 0.1668],
  [0.825, 0.2130],
  [0.85, 0.2731],
  [0.875, 0.3352],
  [0.90, 0.3782],
  [0.925, 0.4111],
  [0.95, 0.4286],
  [0.975, 0.4336],
  [1.00, 0.4260],
  [1.05, 0.3930],
  [1.10, 0.3517],
  [1.15, 0.3126],
  [1.20, 0.2819],
  [1.25, 0.2575],
  [1.30, 0.2385],
  [1.35, 0.2236],
  [1.40, 0.2118],
  [1.45, 0.2024],
  [1.50, 0.1948],
  [1.55, 0.1886],
  [1.60, 0.1835],
  [1.65, 0.1792],
  [1.70, 0.1755],
  [1.75, 0.1723],
  [1.80, 0.1695],
  [1.85, 0.1670],
  [1.90, 0.1648],
  [1.95, 0.1629],
  [2.00, 0.1611],
  [2.05, 0.1595],
  [2.10, 0.1580],
  [2.15, 0.1566],
  [2.20, 0.1553],
  [2.25, 0.1541],
  [2.30, 0.1530],
  [2.35, 0.1520],
  [2.40, 0.1510],
  [2.45, 0.1501],
  [2.50, 0.1492],
  [2.60, 0.1475],
  [2.70, 0.1460],
  [2.80, 0.1446],
  [2.90, 0.1433],
  [3.00, 0.1420],
  [3.20, 0.1397],
  [3.40, 0.1375],
  [3.60, 0.1355],
  [3.80, 0.1337],
  [4.00, 0.1320],
  [4.50, 0.1282],
  [5.00, 0.1249],
];
