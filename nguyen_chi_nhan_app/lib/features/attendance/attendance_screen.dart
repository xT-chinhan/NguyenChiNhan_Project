import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../widgets/site_map.dart';
import '../../widgets/ui.dart';
import '../admin/users_screen.dart' show initialsOf;

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
String dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String duration(int? minutes) {
  if (minutes == null) return '—';
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? '$m phút' : (m == 0 ? '$h giờ' : '$h giờ $m phút');
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 70–75 Chấm công (Nhân viên). API kiểm tra vị trí, giờ, đi trễ; app chỉ gửi GPS và hiển thị.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map? _today;
  Map? _month;
  Object? _error;
  // Vị trí: kết quả API đánh giá (allowed/code/message/distance), hoặc lỗi GPS
  Map? _loc;
  GeoFix? _fix;
  LocationProblem? _locProblem;
  bool _locating = false;
  bool _busy = false;
  Duration _offset = Duration.zero; // giờ máy chủ - giờ máy
  Timer? _tick, _refresh;

  DateTime get _serverNow => DateTime.now().add(_offset);
  String get _status => _today?['status'] ?? 'none';

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _loadToday());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Future.wait([_loadToday(rethrowErrors: true), _loadMonth()]);
      if (_status != 'done') await _locate();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadToday({bool rethrowErrors = false}) async {
    try {
      final t = await Api.i.get('/attendance/today');
      if (!mounted) return;
      setState(() {
        _today = t;
        _offset = DateTime.parse(t['serverTime']).difference(DateTime.now());
      });
    } catch (e) {
      if (rethrowErrors) rethrow;
    }
  }

  Future<void> _loadMonth() async {
    final m = await Api.i.get('/attendance/me');
    if (mounted) setState(() => _month = m);
  }

  /// Lấy GPS -> API đánh giá trong/ngoài khu vực
  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locProblem = null;
    });
    try {
      final fix = await Locator.current();
      final r = await Api.i.post('/attendance/check-location', fix.toJson());
      if (mounted) {
        setState(() {
          _fix = fix;
          _loc = r;
        });
      }
    } on LocationProblem catch (e) {
      if (mounted) {
        setState(() {
          _locProblem = e;
          _loc = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loc = {'allowed': false, 'code': e.code, 'message': e.message, ...e.data});
    } catch (_) {
      if (mounted) setState(() => _locProblem = const LocationProblem('Không lấy được vị trí, thử lại nhé.'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _punch(String action) async {
    setState(() => _busy = true);
    try {
      final fix = await Locator.current();
      final r = await Api.i.post('/attendance/$action', fix.toJson());
      if (!mounted) return;
      toast(context, r['message']);
      await Future.wait([_loadToday(), _loadMonth()]);
    } on LocationProblem catch (e) {
      if (mounted) setState(() => _locProblem = e);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message, error: true);
      if (e.data['allowed'] == false) setState(() => _loc = {'allowed': false, ...e.data, 'message': e.message});
      if (e.code?.startsWith('ALREADY') == true || e.code == 'NOT_CHECKED_IN') _loadToday();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = _today;
    final rec = t?['record'];
    final m = _month;
    final now = _serverNow;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
            const PageHeader('Chấm công'),
            if (_error != null)
              LoadError(_error!, onRetry: _load)
            else ...[
              _todayCard(context, now, rec),
              if (t != null && _status != 'done') ...[const SizedBox(height: 12), _locationBlock(context)],
              const SizedBox(height: 16),
              _actionButton(rec),
              if (t != null) ...[
                const SizedBox(height: 8),
                Text(t['hint'] ?? '', textAlign: TextAlign.center, style: T.bodyS.copyWith(color: c.muted)),
              ],
              const SizedBox(height: 20),
              Text('Tháng ${m == null ? '' : int.parse(m['month'].toString().substring(5))}', style: T.titleM),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _stat(context, 'Ngày công', m?['days']?.toString())),
                const SizedBox(width: 10),
                Expanded(child: _stat(context, 'Tổng giờ', m?['totalHoursText'])),
                const SizedBox(width: 10),
                Expanded(child: _stat(context, 'Đi trễ', m?['lateDays']?.toString(), warn: (m?['lateDays'] ?? 0) > 0)),
              ]),
              const SizedBox(height: 12),
              if (m == null)
                const ListSkeleton(rows: 3)
              else if ((m['items'] as List).isEmpty)
                AppCard(child: Text('Chưa có ngày công nào trong tháng.', style: T.bodyM.copyWith(color: c.muted)))
              else
                AppCard.flush(
                  child: Column(
                    children: withDividers([
                      for (final d in m['items'])
                        ListRow(
                          leading: Bubble(d['late'] == true ? LucideIcons.clock : LucideIcons.calendarDays, tone: d['late'] == true ? Tone.warn : Tone.normal),
                          title: dayLabel(DateTime.parse(d['date'])),
                          subtitle: '${hm(d['checkIn'])} → ${d['checkOut'] == null ? 'đang làm' : hm(d['checkOut'])}${d['late'] == true ? ' · trễ' : ''}',
                          trailing: Text(duration(d['minutes']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, fontFeatures: T.num)),
                        ),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _todayCard(BuildContext context, DateTime now, Map? rec) {
    final c = context.c;
    Widget pill;
    if (_today == null) {
      pill = const Skeleton(width: 80, height: 22, radius: 11);
    } else if (_status == 'working') {
      final mins = now.difference(DateTime.parse(rec!['checkIn'])).inMinutes.clamp(0, 24 * 60);
      pill = Pill('Đang làm ${mins ~/ 60}:${_two(mins % 60)}', icon: LucideIcons.timer, tone: rec['late'] == true ? Tone.warn : Tone.ok);
    } else if (_status == 'done') {
      pill = const Pill('Đã tan ca', icon: LucideIcons.check, tone: Tone.ok);
    } else {
      pill = const Pill('Chưa vào ca');
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Hôm nay · ${dayLabel(now)}', style: T.label.copyWith(color: c.muted)),
          pill,
        ]),
        const SizedBox(height: 8),
        Text('${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}', style: T.display),
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: c.outlineVariant)),
        IntrinsicHeight(
          child: Row(children: [
            Expanded(child: _cell(context, 'Vào ca', rec?['checkIn'], late: rec?['late'] == true)),
            VerticalDivider(width: 1, color: c.outlineVariant),
            const SizedBox(width: 16),
            Expanded(child: _cell(context, 'Tan ca', rec?['checkOut'])),
          ]),
        ),
      ]),
    );
  }

  /// 70 trong khu vực · 74 ngoài khu vực · 75 chưa có GPS
  Widget _locationBlock(BuildContext context) {
    final c = context.c;
    if (_locProblem != null) {
      return Note(
        _locProblem!.message,
        icon: LucideIcons.mapPinOff,
        trailing: GestureDetector(onTap: _locate, child: const Padding(padding: EdgeInsets.only(left: 8), child: Text('Thử lại', style: TextStyle(fontWeight: FontWeight.w600)))),
      );
    }
    final l = _loc;
    if (l == null || _locating && l['allowed'] != true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: c.container, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(LucideIcons.locateFixed, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Text('Đang lấy vị trí…', style: TextStyle(fontSize: 13.5, color: c.muted)),
        ]),
      );
    }
    if (l['allowed'] == true) {
      return GestureDetector(
        onTap: _locate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.successContainer, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(LucideIcons.mapPin, size: 18, color: c.income),
            const SizedBox(width: 10),
            Expanded(child: Text(l['message'], style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.income))),
          ]),
        ),
      );
    }
    final site = l['site'] ?? _today?['site'];
    final title = switch (l['code']) {
      'MOCK_LOCATION' => 'Vị trí giả lập',
      'GPS_INACCURATE' => 'GPS chưa chính xác',
      _ => 'Bạn đang ở ngoài cửa hàng',
    };
    return AppCard.flush(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (site != null && _fix != null)
          SizedBox(
            height: 170,
            child: SiteMap(siteLat: (site['lat'] as num).toDouble(), siteLng: (site['lng'] as num).toDouble(), radius: (site['radius'] as num).toDouble(), meLat: _fix!.lat, meLng: _fix!.lng, okTone: true),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Bubble(LucideIcons.mapPinOff, size: 32, tone: Tone.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(l['message'] ?? '', style: T.bodyS.copyWith(color: c.muted)),
              ]),
            ),
          ]),
        ),
        Center(
          child: TextButton.icon(
            onPressed: _locating ? null : _locate,
            style: TextButton.styleFrom(foregroundColor: c.ink),
            icon: _locating ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.muted)) : const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Cập nhật vị trí', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _actionButton(Map? rec) {
    if (_today == null) return const Btn('Vào ca', icon: LucideIcons.logIn);
    if (_status == 'done') return Btn('Hôm nay đã làm ${duration(rec?['minutes'])}', icon: LucideIcons.calendarCheck);
    if (_locProblem != null) {
      return Column(children: [
        Btn('Bật vị trí', icon: LucideIcons.locateFixed, onTap: () async {
          await Locator.openSettings(serviceOff: _locProblem!.serviceOff);
          if (mounted) _locate();
        }),
        const SizedBox(height: 12),
        Btn.secondary(_status == 'working' ? 'Tan ca' : 'Vào ca', icon: _status == 'working' ? LucideIcons.logOut : LucideIcons.logIn),
      ]);
    }
    final can = _loc?['allowed'] == true && !_locating;
    return _status == 'working'
        ? Btn('Tan ca', icon: LucideIcons.logOut, loading: _busy, onTap: can ? () => _punch('check-out') : null)
        : Btn('Vào ca', icon: LucideIcons.logIn, loading: _busy, onTap: can ? () => _punch('check-in') : null);
  }

  Widget _cell(BuildContext context, String k, dynamic v, {bool late = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: T.label.copyWith(color: context.c.muted)),
        const SizedBox(height: 2),
        Row(children: [
          Text(v == null ? '--:--' : hm(v), style: T.titleM.copyWith(fontFeatures: T.num, color: v == null ? context.c.faint : null)),
          if (late) ...[const SizedBox(width: 6), const Pill('Trễ', tone: Tone.warn, height: 20)],
        ]),
      ]);

  Widget _stat(BuildContext context, String k, String? v, {bool warn = false}) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: T.bodyS.copyWith(color: context.c.muted)),
          const SizedBox(height: 2),
          v == null
              ? const Skeleton(width: 30, height: 20)
              : Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: T.num, color: warn ? context.c.warning : null)),
        ]),
      );
}

/// 73 Admin: ai có mặt, ai trễ, ai chưa vào (theo ngày)
class AttendanceAdminScreen extends StatefulWidget {
  const AttendanceAdminScreen({super.key});
  @override
  State<AttendanceAdminScreen> createState() => _AttendanceAdminScreenState();
}

class _AttendanceAdminScreenState extends State<AttendanceAdminScreen> {
  int _back = 0; // 0 = hôm nay, 1 = hôm qua…
  Map? _d;
  Object? _error;

  DateTime get _date => DateTime.now().subtract(Duration(days: _back));
  String get _iso => '${_date.year}-${_two(_date.month)}-${_two(_date.day)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _d = null;
    });
    try {
      final r = await Api.i.get(_back == 0 ? '/attendance' : '/attendance?date=$_iso');
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _d;
    return Scaffold(
      appBar: const TopBar(back: 'Tài khoản'),
      body: RefreshIndicator(
        color: c.ink,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: kPad), child: Text('Chấm công nhân viên', style: T.headline)),
          const SizedBox(height: 16),
          ChipBar<int>(
            items: [for (var i = 0; i < 7; i++) (i, i == 0 ? 'Hôm nay' : (i == 1 ? 'Hôm qua' : dayLabel(DateTime.now().subtract(Duration(days: i)))))],
            selected: _back,
            onSelect: (i) {
              setState(() => _back = i);
              _load();
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPad),
            child: _error != null
                ? LoadError(_error!, onRetry: _load)
                : d == null
                    ? const ListSkeleton(rows: 4)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AppCard(
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Có mặt', style: T.label.copyWith(color: c.muted)),
                                Text.rich(TextSpan(children: [
                                  TextSpan(text: '${d['present']}', style: T.display),
                                  TextSpan(text: ' / ${d['total']}', style: T.titleL.copyWith(color: c.muted)),
                                ])),
                              ]),
                            ),
                            if (d['late'] > 0) Pill('${d['late']} đi trễ', icon: LucideIcons.clock, tone: Tone.warn),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        if ((d['items'] as List).isEmpty)
                          AppCard(child: Text('Chưa có nhân viên nào.', style: T.bodyM.copyWith(color: c.muted)))
                        else
                          AppCard.flush(
                            child: Column(
                              children: withDividers([
                                for (final u in d['items']) _row(context, u, d['isToday'] == true),
                              ]),
                            ),
                          ),
                      ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, Map u, bool isToday) {
    final r = u['record'];
    String sub;
    Widget pill;
    if (r == null) {
      sub = 'Chưa chấm công';
      pill = Pill(isToday ? 'Chưa vào' : 'Vắng', height: 22);
    } else if (r['checkOut'] == null) {
      sub = 'Vào ${hm(r['checkIn'])}${r['inDistanceText'] != null ? ' · cách ${r['inDistanceText']}' : ''}';
      pill = r['late'] == true ? const Pill('Trễ', tone: Tone.warn, height: 22) : const Pill('Đang làm', tone: Tone.ok, height: 22);
    } else {
      sub = '${hm(r['checkIn'])} → ${hm(r['checkOut'])}${r['inDistanceText'] != null ? ' · ${r['inDistanceText']}' : ''}';
      pill = r['late'] == true ? const Pill('Trễ', tone: Tone.warn, height: 22) : Pill(duration(r['minutes']), tone: Tone.ok, height: 22);
    }
    return ListRow(
      leading: Avatar(initialsOf(u['fullName']), size: 40, color: r == null ? const Color(0xFFB9B7B0) : const Color(0xFF787774)),
      title: u['fullName'],
      subtitle: sub,
      trailing: pill,
    );
  }
}

/// 76 Admin: đặt mốc chấm công (vị trí hiện tại của Admin) + bán kính
class AttendanceSiteScreen extends StatefulWidget {
  const AttendanceSiteScreen({super.key});
  @override
  State<AttendanceSiteScreen> createState() => _AttendanceSiteScreenState();
}

class _AttendanceSiteScreenState extends State<AttendanceSiteScreen> {
  static const _radii = [50, 100, 200, 500];
  Map? _site;
  Object? _error;
  GeoFix? _pending; // vị trí mới chưa lưu
  Map? _pendingPlace; // địa chỉ API tra cho vị trí mới
  int? _radius;
  bool _locating = false;
  bool _saving = false;

  bool get _dirty => _pending != null || (_site != null && _radius != _site!['radius']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await Api.i.get('/attendance/site');
      if (mounted) {
        setState(() {
          _site = s;
          _radius = s['radius'];
          _pending = null;
          _pendingPlace = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final fix = await Locator.current();
      if (!mounted) return;
      setState(() {
        _pending = fix;
        _pendingPlace = null;
      });
      final r = await Api.i.post('/tools/location/resolve', {'lat': fix.lat, 'lng': fix.lng, 'accuracy': fix.accuracy});
      if (mounted) setState(() => _pendingPlace = r);
    } on LocationProblem catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {'radius': _radius, if (_pending != null) ..._pending!.toJson()};
    final r = await guard(context, () => Api.i.put('/attendance/site', body));
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) {
      toast(context, r['message']);
      setState(() {
        _site = r['site'];
        _radius = r['site']['radius'];
        _pending = null;
        _pendingPlace = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _site;
    final lat = _pending?.lat ?? (s?['lat'] as num?)?.toDouble();
    final lng = _pending?.lng ?? (s?['lng'] as num?)?.toDouble();
    final radii = {..._radii, ?_radius}.toList()..sort();
    return Scaffold(
      appBar: const TopBar(back: 'Tài khoản'),
      body: SafeArea(
        top: false,
        child: _error != null
            ? LoadError(_error!, onRetry: _load)
            : Column(children: [
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16), children: [
                    const Text('Vị trí chấm công', style: T.headline),
                    const SizedBox(height: 8),
                    Text('Nhân viên chỉ chấm công được khi ở trong vòng tròn này.', style: T.bodyM.copyWith(color: c.muted)),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 220,
                        decoration: BoxDecoration(border: Border.all(color: c.outline), borderRadius: BorderRadius.circular(18), color: c.container),
                        child: lat == null ? null : SiteMap(siteLat: lat, siteLng: lng!, radius: (_radius ?? 100).toDouble()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      child: s == null
                          ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 140, height: 14), SizedBox(height: 10), Skeleton(width: 220, height: 10)])
                          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Bubble(_pending == null ? LucideIcons.store : LucideIcons.locateFixed, tone: _pending == null ? Tone.normal : Tone.warn),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_pending == null ? s['name'] : 'Vị trí mới · bấm Lưu để áp dụng', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _pending == null
                                        ? '${s['address'] ?? ''} · ${(s['lat'] as num).toStringAsFixed(5)}, ${(s['lng'] as num).toStringAsFixed(5)}'
                                        : '${_pendingPlace == null ? 'Đang tìm địa chỉ…' : '${_pendingPlace!['place']}, ${_pendingPlace!['address']}'} · ±${_pending!.accuracy.round()} m',
                                    style: T.bodyS.copyWith(color: c.muted),
                                  ),
                                ]),
                              ),
                            ]),
                    ),
                    const SizedBox(height: 16),
                    Text('Bán kính cho phép', style: T.label.copyWith(color: c.muted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in radii)
                        Press(
                          onTap: () => setState(() => _radius = r),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: r == _radius ? c.primary : c.surface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: r == _radius ? c.primary : c.outline),
                            ),
                            child: Text('$r m', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: r == _radius ? c.onPrimary : c.ink)),
                          ),
                        ),
                    ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
                  child: Column(children: [
                    Btn.secondary('Đặt tại vị trí hiện tại của tôi', icon: LucideIcons.locateFixed, loading: _locating, onTap: s == null ? null : _useMyLocation),
                    const SizedBox(height: 12),
                    Btn('Lưu', loading: _saving, onTap: _dirty ? _save : null),
                  ]),
                ),
              ]),
      ),
    );
  }
}
