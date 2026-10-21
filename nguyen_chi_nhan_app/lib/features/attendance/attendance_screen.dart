import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../admin/users_screen.dart' show initialsOf;

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
String dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String duration(int? minutes) {
  if (minutes == null) return '—';
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? '$m phút' : (m == 0 ? '$h giờ' : '$h giờ $m phút');
}

/// Chấm công (Nhân viên): mỗi ngày bấm Vào ca, cuối ngày bấm Tan ca. API tính giờ + đi trễ.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map? _today;
  Map? _month;
  Object? _error;
  bool _busy = false;
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([Api.i.get('/attendance/today'), Api.i.get('/attendance/me')]);
      if (mounted) {
        setState(() {
          _today = r[0];
          _month = r[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _punch(String action) async {
    setState(() => _busy = true);
    final r = await guard(context, () => Api.i.post('/attendance/$action'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      toast(context, r['message']);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = _today;
    final rec = t?['record'];
    final status = t?['status'] ?? 'none';
    final m = _month;
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
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Hôm nay · ${dayLabel(_now)}', style: T.label.copyWith(color: c.muted)),
                    if (t == null)
                      const Skeleton(width: 80, height: 22, radius: 11)
                    else if (status == 'working')
                      Pill('Đang làm', icon: LucideIcons.timer, tone: rec['late'] == true ? Tone.warn : Tone.ok)
                    else if (status == 'done')
                      const Pill('Đã tan ca', icon: LucideIcons.check)
                    else
                      const Pill('Chưa vào ca'),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
                    style: T.display,
                  ),
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
              ),
              const SizedBox(height: 16),
              if (status == 'none')
                Btn('Vào ca', icon: LucideIcons.logIn, loading: _busy, onTap: t == null ? null : () => _punch('check-in'))
              else if (status == 'working')
                Btn('Tan ca', icon: LucideIcons.logOut, loading: _busy, onTap: () => _punch('check-out'))
              else
                Btn('Hôm nay đã làm ${duration(rec['minutes'])}', icon: LucideIcons.calendarCheck),
              const SizedBox(height: 8),
              Text('Vào ca sau ${t?['shiftStart'] ?? '08:00'} được tính là đi trễ.', textAlign: TextAlign.center, style: T.bodyS.copyWith(color: c.muted)),
              const SizedBox(height: 20),
              Text('Tháng ${m?['month']?.toString().substring(5) ?? ''}', style: T.titleM),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _stat(context, 'Ngày công', m?['days']?.toString())),
                const SizedBox(width: 10),
                Expanded(child: _stat(context, 'Tổng giờ', m == null ? null : '${((m['totalMinutes'] as int) / 60).toStringAsFixed(1).replaceAll('.', ',')}h')),
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
                          subtitle: '${hm(d['checkIn'])} → ${d['checkOut'] == null ? 'chưa tan ca' : hm(d['checkOut'])}${d['late'] == true ? ' · trễ' : ''}',
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

/// Admin: xem nhân viên đã chấm công trong ngày
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
  String get _iso => '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

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
      final r = await Api.i.get('/attendance?date=$_iso');
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
            items: [
              for (var i = 0; i < 7; i++) (i, i == 0 ? 'Hôm nay' : (i == 1 ? 'Hôm qua' : dayLabel(DateTime.now().subtract(Duration(days: i))))),
            ],
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
                                for (final u in d['items'])
                                  ListRow(
                                    leading: Avatar(initialsOf(u['fullName']), size: 40, color: u['record'] == null ? const Color(0xFFB9B7B0) : const Color(0xFF787774)),
                                    title: u['fullName'],
                                    subtitle: u['record'] == null
                                        ? 'Chưa chấm công'
                                        : '${hm(u['record']['checkIn'])} → ${u['record']['checkOut'] == null ? 'đang làm' : hm(u['record']['checkOut'])}',
                                    trailing: u['record'] == null
                                        ? Pill(_back == 0 ? 'Chưa vào' : 'Vắng', height: 22)
                                        : (u['record']['late'] == true
                                            ? const Pill('Trễ', tone: Tone.warn, height: 22)
                                            : Pill(u['record']['checkOut'] == null ? 'Đang làm' : duration(u['record']['minutes']), tone: Tone.ok, height: 22)),
                                  ),
                              ]),
                            ),
                          ),
                      ]),
          ),
        ]),
      ),
    );
  }
}
