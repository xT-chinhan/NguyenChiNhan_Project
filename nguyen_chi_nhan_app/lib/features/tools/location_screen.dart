import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// 24 / 25 b · Chia sẻ vị trí: GPS trên máy -> API tìm địa chỉ + tạo nội dung chia sẻ
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Position? _pos;
  Map? _place;
  String? _error;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _error = null;
      _place = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Hãy bật Vị trí (GPS) trên điện thoại.';
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw 'Bạn chưa cho phép app dùng vị trí.';
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      if (!mounted) return;
      setState(() => _pos = pos);
      final r = await Api.i.post('/tools/location/resolve', {'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy});
      if (mounted) setState(() => _place = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : 'Không lấy được vị trí, thử lại nhé.');
    }
  }

  Future<void> _share() async {
    final pos = _pos;
    if (pos == null) return;
    setState(() => _sharing = true);
    try {
      final r = await Api.i.post('/tools/location/share', {'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy});
      if (!mounted) return;
      showSheet(
        context,
        (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Gửi vị trí', style: T.titleL),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: ctx.c.container, borderRadius: BorderRadius.circular(14)),
            child: Text(r['shareText'], style: T.bodyS.copyWith(height: 1.55)),
          ),
          const SizedBox(height: 16),
          Btn('Gửi qua Zalo, Messenger, SMS…', icon: LucideIcons.share2, onTap: () {
            Navigator.pop(ctx);
            SharePlus.instance.share(ShareParams(text: r['shareText'], subject: 'Vị trí của tôi'));
          }),
          const SizedBox(height: 10),
          Btn.secondary('Sao chép', icon: LucideIcons.copy, onTap: () {
            Clipboard.setData(ClipboardData(text: r['shareText']));
            Navigator.pop(ctx);
            toast(context, 'Đã sao chép vị trí');
          }),
          const SizedBox(height: 16),
          const Note('Chỉ gửi vị trí lúc bấm. App không theo dõi vị trí sau đó.'),
        ]),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pos = _pos;
    final p = _place;
    return Scaffold(
      appBar: const TopBar(back: 'Tiện ích', title: 'Chia sẻ vị trí'),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 4, kPad, 16), children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 260,
                  decoration: BoxDecoration(color: c.container, border: Border.all(color: c.outline), borderRadius: BorderRadius.circular(18)),
                  child: pos == null
                      ? Center(child: _error == null ? Text('Đang tìm vị trí…', style: T.bodyM.copyWith(color: c.muted)) : Icon(LucideIcons.mapPin, color: c.faint, size: 32))
                      : Stack(children: [
                          Positioned.fill(child: StaticMap(lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy)),
                          Positioned(right: 10, bottom: 10, child: CircleBtn(LucideIcons.locateFixed, onTap: _locate)),
                        ]),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Note(_error!, icon: LucideIcons.circleAlert, trailing: GestureDetector(onTap: _locate, child: const Text('Thử lại', style: TextStyle(fontWeight: FontWeight.w600))))
              else
                AppCard(
                  child: p == null
                      ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 180, height: 14), SizedBox(height: 10), Skeleton(width: 240, height: 10)])
                      : Column(children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Bubble(LucideIcons.mapPin),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p['place'], style: T.body.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(p['address'], style: T.bodyS.copyWith(color: c.muted)),
                              ]),
                            ),
                          ]),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: c.outlineVariant)),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(p['coords'], style: T.bodyS.copyWith(color: c.muted, fontFeatures: T.num)),
                            if (p['accuracyText'] != null) Pill(p['accuracyText'], icon: p['accurate'] == true ? LucideIcons.check : LucideIcons.info, tone: p['accurate'] == true ? Tone.ok : Tone.warn),
                          ]),
                        ]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
            child: Column(children: [
              Btn('Chia sẻ vị trí', icon: LucideIcons.share2, loading: _sharing, onTap: pos == null ? null : _share),
              const SizedBox(height: 12),
              Btn.secondary('Mở Google Maps', icon: LucideIcons.externalLink, onTap: p == null ? null : () => launchUrl(Uri.parse(p['mapsUrl']), mode: LaunchMode.externalApplication)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Bản đồ tĩnh ghép từ tile (CARTO light, tông xám hợp mockup) + chấm vị trí + vòng sai số
class StaticMap extends StatelessWidget {
  final double lat, lng;
  final double accuracy;
  final int zoom;
  const StaticMap({super.key, required this.lat, required this.lng, required this.accuracy, this.zoom = 16});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (_, box) {
      final n = pow(2, zoom).toDouble();
      final px = (lng + 180) / 360 * n * 256;
      final r = lat * pi / 180;
      final py = (1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n * 256;
      final w = box.maxWidth, h = box.maxHeight;
      final left = px - w / 2, top = py - h / 2;
      final tiles = <Widget>[];
      for (var tx = (left / 256).floor(); tx <= ((left + w) / 256).floor(); tx++) {
        for (var ty = (top / 256).floor(); ty <= ((top + h) / 256).floor(); ty++) {
          tiles.add(Positioned(
            left: tx * 256 - left,
            top: ty * 256 - top,
            width: 256,
            height: 256,
            child: Image.network(
              'https://a.basemaps.cartocdn.com/light_all/$zoom/$tx/$ty@2x.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: c.container),
            ),
          ));
        }
      }
      final mpp = 156543.03 * cos(r) / n; // mét / pixel
      final acc = (accuracy / mpp).clamp(14.0, 120.0);
      return Stack(clipBehavior: Clip.hardEdge, children: [
        ...tiles,
        Positioned(
          left: w / 2 - acc,
          top: h / 2 - acc,
          child: Container(
            width: acc * 2,
            height: acc * 2,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x12111111), border: Border.all(color: const Color(0x1F111111))),
          ),
        ),
        Positioned(
          left: w / 2 - 10,
          top: h / 2 - 10,
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
        ),
      ]);
    });
  }
}
