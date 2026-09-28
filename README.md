# Ballistics Calculator

一个专业的 **3D 外弹道计算器**，内置**全球主流制式武器 / 弹药 / 弹头数据库**与**改装系统**，用 Flutter 构建，可通过 GitHub Actions 一键云端打包出 Android APK。

## ✨ 功能特性

### 物理引擎（准确、完整）
- **完整 3D 外弹道**：4 阶 Runge-Kutta（RK4）数值积分
- **多阻力模型可切换**：G1 / G7 标准阻力函数 + 自定义马赫数-Cd 查表
- **ICAO 标准大气**：按温度/气压/湿度/海拔实时计算空气密度、声速
- **风修正**：通过相对速度自然处理横风（drift）与纵风（head/tail）
- **科里奥利 / Eötvös 效应**：按纬度与射击方位角修正地球自转影响
- **Miller 陀螺稳定性**：按缠距/弹长/速度/密度判断弹丸稳定性

### 内置数据库（选型号即用）
- **185 款弹头**（Sierra / Hornady / Nosler / Berger / Lapua 等厂商，含 G1/G7 BC）
- **130 款弹药**（M855、M80、M118LR、MK262、MK318、.338 LM、.50 BMG、6mm Creedmoor、.300 Norma Mag、7mm PRC、.300 PRC…）
- **68 款枪械**，覆盖各国主流制式（军/警/特种）+ 民用：
  - 突击步枪：M4/M16、HK416、AK-74/12、QBZ-95/191、G36、SCAR、Tavor…
  - 狙击/DMR：M24/M40、M110、M2010、Barrett M82/M107、SVD、L115A3、SAKO TRG…
  - 手枪：SIG M17/M18、Beretta M9、Glock、Makarov、QSZ-92…
  - 机枪、冲锋枪、霰弹枪、民用栓动/竞技步枪…

### 改装系统（物理联动）
- **枪管/缠距**：换管长按经验式重算初速；换缠距用 Miller 公式判稳定性（不稳警告）
- **瞄具/归零**：瞄具高度 + 归零距离直接影响 drop/风偏修正
- **枪口装置**：制退器/消音器等对初速的修正

### 输出
- 弹道数据表（距离↔超高/风偏/速度/动能/飞行时间）
- 弹道曲线图、剩余速度曲线图（fl_chart，支持触控读数 tooltip）
- 关键指标一览：最大弹道高、密度高度（DA）、MPBR、跨音速警告、陀螺稳定性
- 实时稳定性反馈、公制/英制单位切换、浅色/深色/跟随系统主题
- DOPE 卡 / CSV 轨迹导出，一键复制到剪贴板

## 📂 项目结构

```
lib/
├── main.dart                 # 应用入口
├── physics/                  # 物理引擎（核心）
│   ├── units.dart            # 单位换算
│   ├── drag_models.dart      # G1/G7 阻力函数
│   ├── atmosphere.dart       # ICAO 空气密度
│   ├── coriolis.dart         # 科里奥利/Eötvös
│   ├── stability.dart        # Miller 稳定性
│   └── ballistics_solver.dart# RK4 积分器
├── models/                   # 数据模型
├── data/assets/              # 内置 JSON 数据库
├── services/                 # 数据管理 + 求解器组装
└── ui/                       # 页面
test/                         # 物理引擎单元测试
assets/data/                  # 枪械/弹药/弹头 JSON
.github/workflows/            # CI 打包
```

## 🔧 本地开发

本仓库**不包含** `android/` 等平台目录（保持可移植）。本地开发需先安装 Flutter，然后：

```bash
flutter create --platforms=android --org com.ballistics --project-name ballistics_calculator .
flutter pub get
flutter test        # 运行物理引擎单元测试
flutter run         # 运行
```

## ☁️ 云端打包 APK（无需本地装环境）

推送代码到 GitHub 后，`.github/workflows/build-apk.yml` 会自动：
1. 安装 Flutter + JDK 17
2. 自动补全 `android/` 平台目录
3. 运行单元测试（物理引擎验证）
4. 编译 release APK
5. 上传为可下载的 artifact

**下载 APK**：GitHub 仓库 → Actions 选项卡 → 选择最近的运行 → Artifacts → `帽子计算器-apk`

## 🌐 Web 版（PWA，浏览器直接用）

推送代码后 `.github/workflows/deploy-web.yml` 自动构建 Flutter Web 并 rsync 部署到服务器（nginx 静态站点，端口 `60195`），部署后自动验证 HTTP 200。所有弹道计算在浏览器本地完成，无需后端。

- **访问**：`http://120.48.13.152:60195/`
- **PWA**：支持"添加到主屏幕"，手机上可像原生应用一样全屏使用（manifest/图标/主题色由 `tools/setup_web_meta.py` 在 CI 中生成）
- **部署密钥**：存于 GitHub Secrets（`MAOZI_DEPLOY_*`），密码不落仓库
- **服务器诊断**：Actions 手动触发 `Server Diagnostics` workflow，可远程查防火墙/解封 IP

## ✅ 物理准确性

物理引擎已用独立 Python 参考实现交叉验证，并与公开弹道表（JBM / Hornady）核对。以 168gr .308 SMK（BC=0.462, MV=2600fps, 200yd 归零）为例：

| 距离 | drop（计算） | 公开参考 |
|------|------------|---------|
| 300yd | -7.8" | -8.1" |
| 500yd | -42.4" | -44.3" |
| 600yd | -70.0" | -73.4" |
