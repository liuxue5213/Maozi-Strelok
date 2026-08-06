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

/// G2 standard drag function (155mm boat-tail, AP-type; long flat-base heavy).
class G2DragModel extends DragModel {
  static final G2DragModel instance = G2DragModel._();
  G2DragModel._();
  static final _TableDragModel _table = _TableDragModel('G2', _g2);
  @override
  String get id => 'G2';
  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// G5 standard drag function (short boat-tail, low-drag flat-base).
class G5DragModel extends DragModel {
  static final G5DragModel instance = G5DragModel._();
  G5DragModel._();
  static final _TableDragModel _table = _TableDragModel('G5', _g5);
  @override
  String get id => 'G5';
  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// G6 standard drag function (flat-base spitzer).
class G6DragModel extends DragModel {
  static final G6DragModel instance = G6DragModel._();
  G6DragModel._();
  static final _TableDragModel _table = _TableDragModel('G6', _g6);
  @override
  String get id => 'G6';
  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// G8 standard drag function (flat-base jacketed; similar to G6).
class G8DragModel extends DragModel {
  static final G8DragModel instance = G8DragModel._();
  G8DragModel._();
  static final _TableDragModel _table = _TableDragModel('G8', _g8);
  @override
  String get id => 'G8';
  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// GI (Ingalls) drag function — the original G1-era standard.
class GiDragModel extends DragModel {
  static final GiDragModel instance = GiDragModel._();
  GiDragModel._();
  static final _TableDragModel _table = _TableDragModel('GI', _gi);
  @override
  String get id => 'GI';
  @override
  double cdRef(double mach) => _table.cdRef(mach);
}

/// GL drag function (Winchester-Western/Lowry high-drag blunt-lead-nose;
/// flat-point/soft-point tubular-magazine bullets). Reconstructed Cd-vs-Mach
/// approximation since JBM publishes GL only in a velocity format.
class GlDragModel extends DragModel {
  static final GlDragModel instance = GlDragModel._();
  GlDragModel._();
  static final _TableDragModel _table = _TableDragModel('GL', _gl);
  @override
  String get id => 'GL';
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

/// All supported standard drag-model identifiers, in display order.
const List<String> dragModelIds = [
  'G1',
  'G2',
  'G5',
  'G6',
  'G7',
  'G8',
  'GI',
  'GL',
];

/// Resolve a drag-model id string into a DragModel instance.
DragModel resolveDragModel(String id) {
  switch (id) {
    case 'G1':
      return G1DragModel.instance;
    case 'G2':
      return G2DragModel.instance;
    case 'G5':
      return G5DragModel.instance;
    case 'G6':
      return G6DragModel.instance;
    case 'G7':
      return G7DragModel.instance;
    case 'G8':
      return G8DragModel.instance;
    case 'GI':
      return GiDragModel.instance;
    case 'GL':
      return GlDragModel.instance;
    case 'Custom':
      return G1DragModel.instance; // placeholder; custom tables supplied directly
    default:
      return G1DragModel.instance;
  }
}

/// Doppler-radar Custom Drag Model (CDM). A bullet-specific Cd-vs-Mach curve
/// measured directly (no form factor / BC needed). Used for ELR accuracy.
/// Unlike [CustomDragModel] (a generic user table), a CDM is the primary drag
/// source and Cd is taken directly from the table without BC scaling.
class DopplerCdm extends DragModel {
  final _TableDragModel _inner;
  DopplerCdm(String name, List<List<double>> table)
      : _inner = _TableDragModel(name, table..sort((a, b) => a[0].compareTo(b[0])));

  @override
  String get id => _inner.id;

  @override
  double cdRef(double mach) => _inner.cdRef(mach);

  /// For a CDM the Cd is taken as-is (no BC / form factor). We override [cd]
  /// so the BC argument is ignored and the measured curve is used directly.
  @override
  double cd(double mach, double bc, double massGr, double diaIn) => cdRef(mach);
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

// ---------------------------------------------------------------------------
// G2 reference drag function (Aberdeen/BRL — verified JBM mcg2.txt).
// 155mm-class boat-tail, heavy AP-type projectile.
// ---------------------------------------------------------------------------
const List<List<double>> _g2 = [
  [0.0, 0.2303], [0.05, 0.2298], [0.1, 0.2287], [0.15, 0.2271], [0.2, 0.2251],
  [0.25, 0.2227], [0.3, 0.2196], [0.35, 0.2156], [0.4, 0.2107], [0.45, 0.2048],
  [0.5, 0.198], [0.55, 0.1905], [0.6, 0.1828], [0.65, 0.1758], [0.7, 0.1702],
  [0.75, 0.1669], [0.775, 0.1664], [0.8, 0.1667], [0.825, 0.1682], [0.85, 0.1711],
  [0.875, 0.1761], [0.9, 0.1831], [0.925, 0.2004], [0.95, 0.2589], [0.975, 0.3492],
  [1.0, 0.3983], [1.025, 0.4075], [1.05, 0.4103], [1.075, 0.4114], [1.1, 0.4106],
  [1.125, 0.4089], [1.15, 0.4068], [1.175, 0.4046], [1.2, 0.4021], [1.25, 0.3966],
  [1.3, 0.3904], [1.35, 0.3835], [1.4, 0.3759], [1.45, 0.3678], [1.5, 0.3594],
  [1.55, 0.3512], [1.6, 0.3432], [1.65, 0.3356], [1.7, 0.3282], [1.75, 0.3213],
  [1.8, 0.3149], [1.85, 0.3089], [1.9, 0.3033], [1.95, 0.2982], [2.0, 0.2933],
  [2.05, 0.2889], [2.1, 0.2846], [2.15, 0.2806], [2.2, 0.2768], [2.25, 0.2731],
  [2.3, 0.2696], [2.35, 0.2663], [2.4, 0.2632], [2.45, 0.2602], [2.5, 0.2572],
  [2.55, 0.2543], [2.6, 0.2515], [2.65, 0.2487], [2.7, 0.246], [2.75, 0.2433],
  [2.8, 0.2408], [2.85, 0.2382], [2.9, 0.2357], [2.95, 0.2333], [3.0, 0.2309],
  [3.1, 0.2262], [3.2, 0.2217], [3.3, 0.2173], [3.4, 0.2132], [3.5, 0.2091],
  [3.6, 0.2052], [3.7, 0.2014], [3.8, 0.1978], [3.9, 0.1944], [4.0, 0.1912],
  [4.2, 0.1851], [4.4, 0.1794], [4.6, 0.1741], [4.8, 0.1693], [5.0, 0.1648],
];

// ---------------------------------------------------------------------------
// G5 reference drag function (Aberdeen/BRL — verified JBM mcg5.txt).
// Short boat-tail, low-drag flat-base bullet.
// ---------------------------------------------------------------------------
const List<List<double>> _g5 = [
  [0.0, 0.171], [0.05, 0.1719], [0.1, 0.1727], [0.15, 0.1732], [0.2, 0.1734],
  [0.25, 0.173], [0.3, 0.1718], [0.35, 0.1696], [0.4, 0.1668], [0.45, 0.1637],
  [0.5, 0.1603], [0.55, 0.1566], [0.6, 0.1529], [0.65, 0.1497], [0.7, 0.1473],
  [0.75, 0.1463], [0.8, 0.1489], [0.85, 0.1583], [0.875, 0.1672], [0.9, 0.1815],
  [0.925, 0.2051], [0.95, 0.2413], [0.975, 0.2884], [1.0, 0.3379], [1.025, 0.3785],
  [1.05, 0.4032], [1.075, 0.4147], [1.1, 0.4201], [1.15, 0.4278], [1.2, 0.4338],
  [1.25, 0.4373], [1.3, 0.4392], [1.35, 0.4403], [1.4, 0.4406], [1.45, 0.4401],
  [1.5, 0.4386], [1.55, 0.4362], [1.6, 0.4328], [1.65, 0.4286], [1.7, 0.4237],
  [1.75, 0.4182], [1.8, 0.4121], [1.85, 0.4057], [1.9, 0.3991], [1.95, 0.3926],
  [2.0, 0.3861], [2.05, 0.38], [2.1, 0.3741], [2.15, 0.3684], [2.2, 0.363],
  [2.25, 0.3578], [2.3, 0.3529], [2.35, 0.3481], [2.4, 0.3435], [2.45, 0.3391],
  [2.5, 0.3349], [2.6, 0.3269], [2.7, 0.3194], [2.8, 0.3125], [2.9, 0.306],
  [3.0, 0.2999], [3.1, 0.2942], [3.2, 0.2889], [3.3, 0.2838], [3.4, 0.279],
  [3.5, 0.2745], [3.6, 0.2703], [3.7, 0.2662], [3.8, 0.2624], [3.9, 0.2588],
  [4.0, 0.2553], [4.2, 0.2488], [4.4, 0.2429], [4.6, 0.2376], [4.8, 0.2326],
  [5.0, 0.228],
];

// ---------------------------------------------------------------------------
// G6 reference drag function (Aberdeen/BRL — verified JBM mcg6.txt).
// Flat-base spitzer bullet.
// ---------------------------------------------------------------------------
const List<List<double>> _g6 = [
  [0.0, 0.2617], [0.05, 0.2553], [0.1, 0.2491], [0.15, 0.2432], [0.2, 0.2376],
  [0.25, 0.2324], [0.3, 0.2278], [0.35, 0.2238], [0.4, 0.2205], [0.45, 0.2177],
  [0.5, 0.2155], [0.55, 0.2138], [0.6, 0.2126], [0.65, 0.2121], [0.7, 0.2122],
  [0.75, 0.2132], [0.8, 0.2154], [0.85, 0.2194], [0.875, 0.2229], [0.9, 0.2297],
  [0.925, 0.2449], [0.95, 0.2732], [0.975, 0.3141], [1.0, 0.3597], [1.025, 0.3994],
  [1.05, 0.4261], [1.075, 0.4402], [1.1, 0.4465], [1.125, 0.449], [1.15, 0.4497],
  [1.175, 0.4494], [1.2, 0.4482], [1.225, 0.4464], [1.25, 0.4441], [1.3, 0.439],
  [1.35, 0.4336], [1.4, 0.4279], [1.45, 0.4221], [1.5, 0.4162], [1.55, 0.4102],
  [1.6, 0.4042], [1.65, 0.3981], [1.7, 0.3919], [1.75, 0.3855], [1.8, 0.3788],
  [1.85, 0.3721], [1.9, 0.3652], [1.95, 0.3583], [2.0, 0.3515], [2.05, 0.3447],
  [2.1, 0.3381], [2.15, 0.3314], [2.2, 0.3249], [2.25, 0.3185], [2.3, 0.3122],
  [2.35, 0.306], [2.4, 0.3], [2.45, 0.2941], [2.5, 0.2883], [2.6, 0.2772],
  [2.7, 0.2668], [2.8, 0.2574], [2.9, 0.2487], [3.0, 0.2407], [3.1, 0.2333],
  [3.2, 0.2265], [3.3, 0.2202], [3.4, 0.2144], [3.5, 0.2089], [3.6, 0.2039],
  [3.7, 0.1991], [3.8, 0.1947], [3.9, 0.1905], [4.0, 0.1866], [4.2, 0.1794],
  [4.4, 0.173], [4.6, 0.1673], [4.8, 0.1621], [5.0, 0.1574],
];

// ---------------------------------------------------------------------------
// G8 reference drag function (Aberdeen/BRL — verified JBM mcg8.txt).
// Flat-base jacketed bullet.
// ---------------------------------------------------------------------------
const List<List<double>> _g8 = [
  [0.0, 0.2105], [0.05, 0.2105], [0.1, 0.2104], [0.15, 0.2104], [0.2, 0.2103],
  [0.25, 0.2103], [0.3, 0.2103], [0.35, 0.2103], [0.4, 0.2103], [0.45, 0.2102],
  [0.5, 0.2102], [0.55, 0.2102], [0.6, 0.2102], [0.65, 0.2102], [0.7, 0.2103],
  [0.75, 0.2103], [0.8, 0.2104], [0.825, 0.2104], [0.85, 0.2105], [0.875, 0.2106],
  [0.9, 0.2109], [0.925, 0.2183], [0.95, 0.2571], [0.975, 0.3358], [1.0, 0.4068],
  [1.025, 0.4378], [1.05, 0.4476], [1.075, 0.4493], [1.1, 0.4477], [1.125, 0.445],
  [1.15, 0.4419], [1.2, 0.4353], [1.25, 0.4283], [1.3, 0.4208], [1.35, 0.4133],
  [1.4, 0.4059], [1.45, 0.3986], [1.5, 0.3915], [1.55, 0.3845], [1.6, 0.3777],
  [1.65, 0.371], [1.7, 0.3645], [1.75, 0.3581], [1.8, 0.3519], [1.85, 0.3458],
  [1.9, 0.34], [1.95, 0.3343], [2.0, 0.3288], [2.05, 0.3234], [2.1, 0.3182],
  [2.15, 0.3131], [2.2, 0.3081], [2.25, 0.3032], [2.3, 0.2983], [2.35, 0.2937],
  [2.4, 0.2891], [2.45, 0.2845], [2.5, 0.2802], [2.6, 0.272], [2.7, 0.2642],
  [2.8, 0.2569], [2.9, 0.2499], [3.0, 0.2432], [3.1, 0.2368], [3.2, 0.2308],
  [3.3, 0.2251], [3.4, 0.2197], [3.5, 0.2147], [3.6, 0.2101], [3.7, 0.2058],
  [3.8, 0.2019], [3.9, 0.1983], [4.0, 0.195], [4.2, 0.189], [4.4, 0.1837],
  [4.6, 0.1791], [4.8, 0.175], [5.0, 0.1713],
];

// ---------------------------------------------------------------------------
// GI (Ingalls) reference drag function (Aberdeen/BRL — verified JBM mcgi.txt).
// The original historical standard.
// ---------------------------------------------------------------------------
const List<List<double>> _gi = [
  [0.0, 0.2282], [0.05, 0.2282], [0.1, 0.2282], [0.15, 0.2282], [0.2, 0.2282],
  [0.25, 0.2282], [0.3, 0.2282], [0.35, 0.2282], [0.4, 0.2282], [0.45, 0.2282],
  [0.5, 0.2282], [0.55, 0.2282], [0.6, 0.2282], [0.65, 0.2282], [0.7, 0.2282],
  [0.725, 0.2353], [0.75, 0.2434], [0.775, 0.2515], [0.8, 0.2596], [0.825, 0.2677],
  [0.85, 0.2759], [0.875, 0.2913], [0.9, 0.317], [0.925, 0.3442], [0.95, 0.3728],
  [1.0, 0.4349], [1.05, 0.5034], [1.075, 0.5402], [1.1, 0.5756], [1.125, 0.5887],
  [1.15, 0.6018], [1.175, 0.6149], [1.2, 0.6279], [1.225, 0.6418], [1.25, 0.6423],
  [1.3, 0.6423], [1.35, 0.6423], [1.4, 0.6423], [1.45, 0.6423], [1.5, 0.6423],
  [1.55, 0.6423], [1.6, 0.6423], [1.625, 0.6407], [1.65, 0.6378], [1.7, 0.6321],
  [1.75, 0.6266], [1.8, 0.6213], [1.85, 0.6163], [1.9, 0.6113], [1.95, 0.6066],
  [2.0, 0.602], [2.05, 0.5976], [2.1, 0.5933], [2.15, 0.5891], [2.2, 0.585],
  [2.25, 0.5811], [2.3, 0.5773], [2.35, 0.5733], [2.4, 0.5679], [2.45, 0.5626],
  [2.5, 0.5576], [2.6, 0.5478], [2.7, 0.5386], [2.8, 0.5298], [2.9, 0.5215],
  [3.0, 0.5136], [3.1, 0.5061], [3.2, 0.4989], [3.3, 0.4921], [3.4, 0.4855],
  [3.5, 0.4792], [3.6, 0.4732], [3.7, 0.4674], [3.8, 0.4618], [3.9, 0.4564],
  [4.0, 0.4513], [4.2, 0.4415], [4.4, 0.4323], [4.6, 0.4238], [4.8, 0.4157],
  [5.0, 0.4082],
];

// ---------------------------------------------------------------------------
// GL — Winchester-Western (Lowry 1965) high-drag blunt-lead-nose standard for
// flat-point / soft-point tubular-magazine bullets. NOTE: JBM publishes GL
// only in a velocity-based format truncated at ~Mach 3.2 (no full Cd-vs-Mach
// table), so this is a reconstructed Cd-vs-Mach approximation of that
// high-drag blunt-nose profile. Use G7 for modern low-drag boat-tail bullets.
// ---------------------------------------------------------------------------
const List<List<double>> _gl = [
  [0.0, 0.350], [0.1, 0.348], [0.2, 0.344], [0.3, 0.340], [0.4, 0.336],
  [0.5, 0.332], [0.6, 0.330], [0.7, 0.338], [0.8, 0.400], [0.85, 0.460],
  [0.9, 0.560], [0.95, 0.680], [1.0, 0.760], [1.05, 0.720], [1.1, 0.640],
  [1.2, 0.540], [1.3, 0.480], [1.4, 0.440], [1.5, 0.415], [1.6, 0.400],
  [1.7, 0.390], [1.8, 0.382], [1.9, 0.376], [2.0, 0.370], [2.2, 0.362],
  [2.4, 0.356], [2.6, 0.350], [2.8, 0.345], [3.0, 0.341], [3.2, 0.337],
  [3.4, 0.334], [3.6, 0.331], [3.8, 0.328], [4.0, 0.326], [4.5, 0.321],
  [5.0, 0.317],
];
