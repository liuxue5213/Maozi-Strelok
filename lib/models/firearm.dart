/// Category a firearm belongs to, used for browsing/filtering.
enum FirearmCategory {
  pistol, // 手枪
  assaultRifle, // 突击步枪
  battleRifle, // 战斗步枪（全威力弹）
  sniper, // 狙击步枪
  dmr, // 精确射手步枪
  machineGun, // 通用机枪
  heavyMG, // 重机枪
  smg, // 冲锋枪
  pdw, // 个人防卫武器
  shotgun, // 霰弹枪
  boltRifle, // 栓动步枪（民用/狩猎/竞技）
  antiMaterial, // 反器材步枪
}

/// Usage / role tags for filtering.
enum FirearmRole {
  military, // 军用
  police, // 警用
  specialForces, // 特种部队
  civilian, // 民用
  competition, // 竞技
  hunting, // 狩猎
}

/// A bullet (projectile): manufacturer + model with its ballistic properties.
class Bullet {
  final String id;
  final String manufacturer;
  final String model;
  final String caliber; // e.g. ".308 Win", "5.56 NATO"
  final double massGr;
  final double diameterIn;
  final double lengthIn; // for Miller stability
  final double bcG1; // G1 ballistic coefficient
  final double? bcG7; // G7 ballistic coefficient (if published)
  final BulletType type;

  const Bullet({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.caliber,
    required this.massGr,
    required this.diameterIn,
    required this.lengthIn,
    required this.bcG1,
    this.bcG7,
    required this.type,
  });

  factory Bullet.fromJson(Map<String, dynamic> j) => Bullet(
        id: j['id'] as String,
        manufacturer: j['manufacturer'] as String,
        model: j['model'] as String,
        caliber: j['caliber'] as String,
        massGr: (j['massGr'] as num).toDouble(),
        diameterIn: (j['diameterIn'] as num).toDouble(),
        lengthIn: (j['lengthIn'] as num).toDouble(),
        bcG1: (j['bcG1'] as num).toDouble(),
        bcG7: (j['bcG7'] as num?)?.toDouble(),
        type: BulletType.values.byName(j['type'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'manufacturer': manufacturer,
        'model': model,
        'caliber': caliber,
        'massGr': massGr,
        'diameterIn': diameterIn,
        'lengthIn': lengthIn,
        'bcG1': bcG1,
        if (bcG7 != null) 'bcG7': bcG7,
        'type': type.name,
      };
}

/// Bullet construction / profile type.
enum BulletType {
  fmj, // 全金属被甲
  hp, // 空尖
  hpbt, // 空尖船尾（match）
  sp, // 软尖
  openTip, // 尖顶开尖
  bthp, // 船尾空尖
  ap, // 穿甲
  tracer, // 曳光
  subsonic, // 亚音速
  slug, // 霰弹独头
  shotgunShell, // 霰弹
}

/// A factory cartridge/load: a specific ammunition product.
class Cartridge {
  final String id;
  final String designation; // e.g. "M855", "GGg DM111"
  final String manufacturer;
  final String caliber;
  final double muzzleVelocityFps; // nominal MV at reference barrel length
  final double refBarrelLengthIn; // barrel length the MV is quoted at
  final String bulletId; // link to a Bullet
  final String? notes;

  const Cartridge({
    required this.id,
    required this.designation,
    required this.manufacturer,
    required this.caliber,
    required this.muzzleVelocityFps,
    required this.refBarrelLengthIn,
    required this.bulletId,
    this.notes,
  });

  factory Cartridge.fromJson(Map<String, dynamic> j) => Cartridge(
        id: j['id'] as String,
        designation: j['designation'] as String,
        manufacturer: j['manufacturer'] as String,
        caliber: j['caliber'] as String,
        muzzleVelocityFps: (j['muzzleVelocityFps'] as num).toDouble(),
        refBarrelLengthIn: (j['refBarrelLengthIn'] as num).toDouble(),
        bulletId: j['bulletId'] as String,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'designation': designation,
        'manufacturer': manufacturer,
        'caliber': caliber,
        'muzzleVelocityFps': muzzleVelocityFps,
        'refBarrelLengthIn': refBarrelLengthIn,
        'bulletId': bulletId,
        if (notes != null) 'notes': notes,
      };
}

/// A firearm platform.
class Firearm {
  final String id;
  final String name;
  final String manufacturer;
  final String country;
  final FirearmCategory category;
  final List<FirearmRole> roles;
  final List<String> compatibleCalibers;
  final double barrelLengthIn; // default barrel length
  final double twistRateIn; // inches per turn
  final double sightHeightIn; // default sight height
  final String defaultCartridgeId;
  final int yearIntroduced;
  final String? notes;

  const Firearm({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.country,
    required this.category,
    required this.roles,
    required this.compatibleCalibers,
    required this.barrelLengthIn,
    required this.twistRateIn,
    required this.sightHeightIn,
    required this.defaultCartridgeId,
    required this.yearIntroduced,
    this.notes,
  });

  factory Firearm.fromJson(Map<String, dynamic> j) => Firearm(
        id: j['id'] as String,
        name: j['name'] as String,
        manufacturer: j['manufacturer'] as String,
        country: j['country'] as String,
        category: FirearmCategory.values.byName(j['category'] as String),
        roles: (j['roles'] as List)
            .map((e) => FirearmRole.values.byName(e as String))
            .toList(),
        compatibleCalibers:
            (j['compatibleCalibers'] as List).cast<String>(),
        barrelLengthIn: (j['barrelLengthIn'] as num).toDouble(),
        twistRateIn: (j['twistRateIn'] as num).toDouble(),
        sightHeightIn: (j['sightHeightIn'] as num).toDouble(),
        defaultCartridgeId: j['defaultCartridgeId'] as String,
        yearIntroduced: (j['yearIntroduced'] as num).toInt(),
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'manufacturer': manufacturer,
        'country': country,
        'category': category.name,
        'roles': roles.map((e) => e.name).toList(),
        'compatibleCalibers': compatibleCalibers,
        'barrelLengthIn': barrelLengthIn,
        'twistRateIn': twistRateIn,
        'sightHeightIn': sightHeightIn,
        'defaultCartridgeId': defaultCartridgeId,
        'yearIntroduced': yearIntroduced,
        if (notes != null) 'notes': notes,
      };
}
