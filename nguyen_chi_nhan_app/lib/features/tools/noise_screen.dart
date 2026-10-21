import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'noise/noise_source.dart';

/// 22 / 23 d · Đo tiếng ồn: micro đo dB trên máy, bảng mức + đánh giá lấy từ API
class NoiseScreen extends StatefulWidget {
  const NoiseScreen({super.key});
  @override
  State<NoiseScreen> createState() => _NoiseScreenState();
}

class _NoiseScreenState extends State<NoiseScreen> {
  final _source = NoiseSource();
  Timer? _tick;
  Map? _cfg; // {levels, scale, warnText} từ API
  double _now = 0, _sum = 0, _max = 0;
  int _count = 0, _secs = 0;
  final _bars = <double>[];
  bool _running = false;
  bool _saving = false;
  String? _error;

  List get _levels => (_cfg?['levels'] as List?) ?? const [];
  num get _warn => (_cfg?['scale']?['warn'] as num?) ?? 85;

  @override
  void initState() {
    super.initState();
    _loadLevels();
    if (!NoiseSource.needsTap) _start(); // web: chờ người dùng bấm Bắt đầu đo
  }

  @override
  void dispose() {
    _source.stop();
    _tick?.cancel();
    super.dispose();
  }

  // Bảng mức lấy từ API, lưu lại để vẫn dùng được khi mất mạng
  Future<void> _loadLevels() async {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString('noise_levels');
    if (cached != null && mounted) setState(() => _cfg = jsonDecode(cached));
    try {
      final r = await Api.i.get('/tools/noise/levels');
      await p.setString('noise_levels', jsonEncode(r));
      if (mounted) setState(() => _cfg = r);
    } catch (_) {}
  }

  Map? _levelOf(num db) {
    for (final l in _levels) {
      if (db < (l['max'] as num)) return l;
    }
    return _levels.isEmpty ? null : _levels.last;
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _running = true;
      _now = _sum = _max = 0;
      _count = _secs = 0;
      _bars.clear();
    });
    final err = await _source.start((x) {
      _now = x.$1;
      _sum += x.$1;
      _count++;
      _max = max(_max, x.$2);
    });
    if (err != null) {
      if (mounted) {
        setState(() {
          _error = err;
          _running = false;
        });
      }
      return;
    }
    // Cập nhật giao diện 2 lần/giây, cột sóng 20 mẫu gần nhất
    var half = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _bars.add(_now);
        if (_bars.length > 60) _bars.removeAt(0);
        if (++half % 2 == 0) _secs++;
      });
    });
  }

  Future<void> _stop() async {
    await _source.stop();
    _tick?.cancel();
    setState(() => _running = false);
    if (_count == 0 || _secs == 0) return;
    setState(() => _saving = true);
    try {
      final r = await Api.i.post('/tools/noise/records', {'avgDb': _sum / _count, 'maxDb': max(_max, _sum / _count), 'durationSec': _secs});
      if (!mounted) return;
      final lv = r['level'];
      final tone = lv['tone'] == 'danger' ? Tone.danger : (lv['tone'] == 'warn' ? Tone.warn : Tone.ok);
      showSheet(
        context,
        (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Bubble(LucideIcons.ear, size: 56, tone: tone)),
          const SizedBox(height: 14),
          Text('Đã lưu lần đo · ${lv['label']}', textAlign: TextAlign.center, style: T.titleL),
          const SizedBox(height: 6),
          Text(r['advice'], textAlign: TextAlign.center, style: T.bodyM.copyWith(color: ctx.c.muted)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _Stat('Trung bình', '${r['avgDb']} dB')),
            const SizedBox(width: 12),
            Expanded(child: _Stat('Cao nhất', '${r['maxDb']} dB')),
          ]),
          const SizedBox(height: 18),
          Btn('Xong', onTap: () => Navigator.pop(ctx)),
        ]),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _time => '${(_secs ~/ 60).toString().padLeft(2, '0')}:${(_secs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final loud = _now >= _warn;
    final lv = _levelOf(_now);
    final avg = _count == 0 ? 0 : _sum / _count;
    final shown = _bars.length > 20 ? _bars.sublist(_bars.length - 20) : _bars;
    return Scaffold(
      appBar: const TopBar(back: 'Tiện ích', title: 'Đo tiếng ồn'),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 4, kPad, 16), children: [
              if (_error != null) ...[Note(_error!, icon: LucideIcons.circleAlert), const SizedBox(height: 12)],
              AppCard(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Column(children: [
                  loud
                      ? Pill('Quá ồn · $_time', icon: LucideIcons.ear, tone: Tone.danger)
                      : Pill(_running ? 'Đang đo · $_time' : (_count == 0 ? 'Bấm Bắt đầu đo' : 'Đã dừng · $_time'), icon: _running ? LucideIcons.circle : LucideIcons.pause),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _now.round().toString()),
                      TextSpan(text: ' dB', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0, color: c.muted)),
                    ]),
                    style: TextStyle(fontSize: 72, fontWeight: FontWeight.w700, letterSpacing: -2.8, height: 1.1, color: loud ? c.danger : c.ink, fontFeatures: T.num),
                  ),
                  Text(lv?['example'] ?? (_running ? 'Đang nghe…' : ' '), style: T.bodyM.copyWith(color: c.muted)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 72,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (var i = 0; i < 20; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(
                          child: Builder(builder: (_) {
                            final k = i - (20 - shown.length);
                            if (k < 0) return const SizedBox();
                            final v = shown[k];
                            final h = ((v - 30) / 70).clamp(.08, 1.0);
                            final old = k < shown.length - 10;
                            return FractionallySizedBox(
                              heightFactor: h,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: v >= _warn ? c.warningBar : c.ink.withValues(alpha: old ? .22 : .85),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('10 giây trước', style: T.bodyS.copyWith(color: c.faint)),
                    Text('bây giờ', style: T.bodyS.copyWith(color: c.faint)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Stat('Trung bình', '${avg.round()} dB')),
                const SizedBox(width: 12),
                Expanded(child: _Stat('Cao nhất', '${_max.round()} dB')),
              ]),
              const SizedBox(height: 12),
              if (loud && _levels.isNotEmpty)
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: withDividers([
                      for (final l in _levels.where((l) => (l['min'] as num) <= _now))
                        SizedBox(
                          height: 44,
                          child: Row(children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: l['tone'] == 'danger' ? c.dangerBar : (l['tone'] == 'warn' ? c.warningBar : const Color(0xFFDAD8D2)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(width: 56, child: Text('${l == lv ? _now.round() : l['min']} dB', style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: T.num))),
                            Expanded(
                              child: Text(
                                l == lv ? 'Bạn đang ở đây · ${l['label']}' : l['example'],
                                style: TextStyle(fontSize: 14, color: l == lv ? c.ink : c.muted, fontWeight: l == lv ? FontWeight.w600 : FontWeight.w400),
                              ),
                            ),
                          ]),
                        ),
                    ], indent: 0),
                  ),
                )
              else
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LayoutBuilder(
                      builder: (_, box) => SizedBox(
                        height: 18,
                        child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(colors: [
                                const Color(0xFFDAD8D2),
                                const Color(0xFFDAD8D2),
                                c.warningBar,
                                c.warningBar,
                                c.dangerBar,
                                c.dangerBar,
                              ], stops: const [0, .55, .55, .77, .77, 1]),
                            ),
                          ),
                          Positioned(
                            left: ((_now - 30) / 90).clamp(0.0, 1.0) * (box.maxWidth - 4),
                            child: Container(width: 4, height: 18, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2), border: Border.all(color: c.surface, width: 1))),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      for (final t in ['30', '60', '85', '120 dB']) Text(t, style: T.bodyS.copyWith(color: c.muted, fontFeatures: T.num)),
                    ]),
                    const SizedBox(height: 12),
                    Text(_cfg?['warnText'] ?? 'Trên 85 dB nghe lâu có thể hại tai.', style: T.bodyS.copyWith(color: c.muted)),
                  ]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
            child: Row(children: [
              Expanded(
                flex: 10,
                child: Btn.secondary('Đo lại', icon: LucideIcons.refreshCw, onTap: () async {
                  await _source.stop();
                  _tick?.cancel();
                  _start();
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                child: _running ? Btn('Dừng & lưu', icon: LucideIcons.square, loading: _saving, onTap: _stop) : Btn('Bắt đầu đo', icon: LucideIcons.mic, onTap: _start),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String k, v;
  const _Stat(this.k, this.v);
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: T.bodyS.copyWith(color: context.c.muted)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, fontFeatures: T.num)),
        ]),
      );
}
