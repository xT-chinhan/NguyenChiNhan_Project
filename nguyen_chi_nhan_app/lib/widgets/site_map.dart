import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Bản đồ tĩnh (tile CARTO light) có vòng bán kính cửa hàng, ô vuông mốc và chấm vị trí của tôi.
/// Tự chọn mức zoom để thấy cả mốc lẫn vị trí của tôi.
class SiteMap extends StatelessWidget {
  final double siteLat, siteLng, radius;
  final double? meLat, meLng;
  final bool okTone; // vòng xanh (màn chấm công) hay mực (màn Admin)
  const SiteMap({super.key, required this.siteLat, required this.siteLng, required this.radius, this.meLat, this.meLng, this.okTone = false});

  static Offset _px(double lat, double lng, int z) {
    final n = pow(2, z).toDouble() * 256;
    final r = lat * pi / 180;
    return Offset((lng + 180) / 360 * n, (1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final hasMe = meLat != null && meLng != null;
      final cLat = hasMe ? (siteLat + meLat!) / 2 : siteLat;
      final cLng = hasMe ? (siteLng + meLng!) / 2 : siteLng;
      // khoảng cách cần thấy (m) -> zoom
      final cosLat = cos(cLat * pi / 180);
      double span = radius * 2.4;
      if (hasMe) {
        final dy = (siteLat - meLat!) * 111320, dx = (siteLng - meLng!) * 111320 * cosLat;
        span = max(span, sqrt(dx * dx + dy * dy) + radius * 2);
      }
      final z = (log(156543.03 * cosLat * min(w, h) * .8 / span) / ln2).floor().clamp(3, 18);
      final center = _px(cLat, cLng, z);
      final left = center.dx - w / 2, top = center.dy - h / 2;
      Offset at(double lat, double lng) => _px(lat, lng, z) - Offset(left, top);
      final mpp = 156543.03 * cosLat / pow(2, z);
      final tiles = <Widget>[
        for (var tx = (left / 256).floor(); tx <= ((left + w) / 256).floor(); tx++)
          for (var ty = (top / 256).floor(); ty <= ((top + h) / 256).floor(); ty++)
            Positioned(
              left: tx * 256 - left,
              top: ty * 256 - top,
              width: 256,
              height: 256,
              child: Image.network(
                'https://a.basemaps.cartocdn.com/light_all/$z/$tx/$ty@2x.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: c.container),
              ),
            ),
      ];
      final site = at(siteLat, siteLng);
      final ring = okTone ? c.income : c.ink;
      return Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(child: Container(color: c.container)),
        ...tiles,
        Positioned.fill(child: CustomPaint(painter: _Ring(site, radius / mpp, ring))),
        Positioned(
          left: site.dx - 11,
          top: site.dy - 11,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: okTone ? c.income : const Color(0xFF111111), borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white, width: 3)),
          ),
        ),
        if (hasMe)
          Builder(builder: (_) {
            final me = at(meLat!, meLng!);
            return Positioned(
              left: me.dx - 10,
              top: me.dy - 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF111111),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [BoxShadow(color: Color(0x4D111111), blurRadius: 12, offset: Offset(0, 4))],
                ),
              ),
            );
          }),
      ]);
    });
  }
}

/// Vòng tròn nét đứt + nền nhạt = bán kính cho phép
class _Ring extends CustomPainter {
  final Offset center;
  final double r;
  final Color color;
  _Ring(this.center, this.r, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(center, r, Paint()..color = color.withValues(alpha: .09));
    final p = Paint()
      ..color = color.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 5.0;
    final circ = 2 * pi * r;
    final n = max(8, (circ / (dash + gap)).floor());
    final step = 2 * pi / n;
    final sweep = step * dash / (dash + gap);
    for (var i = 0; i < n; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), i * step, sweep, false, p);
    }
  }

  @override
  bool shouldRepaint(_Ring o) => o.center != center || o.r != r || o.color != color;
}
