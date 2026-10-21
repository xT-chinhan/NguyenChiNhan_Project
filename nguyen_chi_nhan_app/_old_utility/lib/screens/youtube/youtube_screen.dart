import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../theme/app_theme.dart';

class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});

  // Preset sample videos for immediate testing
  static const List<Map<String, String>> sampleVideos = [
    {
      'title': 'Flutter in 100 Seconds',
      'id': 'l-epqV_Uv1s',
      'author': 'Fireship',
    },
    {
      'title': 'Building Beautiful UIs with Flutter',
      'id': 'b_sQ9bMltGU',
      'author': 'Flutter Official',
    },
    {
      'title': 'Lofi Hip Hop Radio - Beats to Relax',
      'id': 'jfKfPfyJRdk',
      'author': 'Lofi Girl',
    },
    {
      'title': 'Big Buck Bunny (Sample HD)',
      'id': 'aqz-KE-bpKQ',
      'author': 'Blender Foundation',
    },
  ];

  static String? extractVideoId(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;

    // Direct 11-character video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    // Try official helper first
    try {
      final helperId = YoutubePlayerController.convertUrlToId(trimmed);
      if (helperId != null && helperId.length == 11) {
        return helperId;
      }
    } catch (_) {}

    // Normalize URL scheme if missing
    var urlToParse = trimmed;
    if (!urlToParse.startsWith('http://') && !urlToParse.startsWith('https://')) {
      urlToParse = 'https://$urlToParse';
    }

    final uri = Uri.tryParse(urlToParse);
    if (uri != null) {
      if (uri.queryParameters.containsKey('v')) {
        final v = uri.queryParameters['v']!;
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v)) {
          return v;
        }
      }
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        final id = uri.pathSegments[0];
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
          return id;
        }
      }
      if (uri.pathSegments.contains('shorts') || uri.pathSegments.contains('embed') || uri.pathSegments.contains('v')) {
        final idx = uri.pathSegments.indexWhere((s) => s == 'shorts' || s == 'embed' || s == 'v');
        if (idx >= 0 && idx + 1 < uri.pathSegments.length) {
          final id = uri.pathSegments[idx + 1];
          if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
            return id;
          }
        }
      }
    }

    // Extra regex fallback for any other formatted YouTube URL
    try {
      final regExp = RegExp(
        r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?.*v=|shorts\/))([a-zA-Z0-9_-]{11})',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(trimmed);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  final TextEditingController _urlController = TextEditingController();
  YoutubePlayerController? _controller;
  String? _currentVideoId;
  String? _errorMessage;
  bool _isPlaying = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    // Default video ready to play
    _loadVideoById('l-epqV_Uv1s');
  }

  void _loadVideoById(String videoId, {bool autoPlay = false}) {
    setState(() {
      _currentVideoId = videoId;
      _errorMessage = null;
      _urlController.text = 'https://youtu.be/$videoId';
    });

    try {
      if (_controller == null) {
        _controller = YoutubePlayerController.fromVideoId(
          videoId: videoId,
          autoPlay: autoPlay,
          params: const YoutubePlayerParams(
            showControls: true,
            showFullscreenButton: true,
            mute: false,
          ),
        );

        _controller!.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state.playerState == PlayerState.playing;
            });
          }
        });
      } else {
        if (autoPlay) {
          _controller!.loadVideoById(videoId: videoId);
          _controller!.playVideo();
          setState(() {
            _isPlaying = true;
          });
        } else {
          _controller!.cueVideoById(videoId: videoId);
        }
      }
    } catch (e) {
      debugPrint('Youtube player initialization skipped or platform unavailable: $e');
    }
  }

  String? _extractVideoId(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;

    // Direct 11-character video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    // Try official helper first
    try {
      final helperId = YoutubePlayerController.convertUrlToId(trimmed);
      if (helperId != null && helperId.length == 11) {
        return helperId;
      }
    } catch (_) {}

    // Normalize URL scheme if missing
    var urlToParse = trimmed;
    if (!urlToParse.startsWith('http://') && !urlToParse.startsWith('https://')) {
      urlToParse = 'https://$urlToParse';
    }

    final uri = Uri.tryParse(urlToParse);
    if (uri != null) {
      if (uri.queryParameters.containsKey('v')) {
        final v = uri.queryParameters['v']!;
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v)) {
          return v;
        }
      }
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        final id = uri.pathSegments[0];
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
          return id;
        }
      }
      if (uri.pathSegments.contains('shorts') || uri.pathSegments.contains('embed') || uri.pathSegments.contains('v')) {
        final idx = uri.pathSegments.indexWhere((s) => s == 'shorts' || s == 'embed' || s == 'v');
        if (idx >= 0 && idx + 1 < uri.pathSegments.length) {
          final id = uri.pathSegments[idx + 1];
          if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
            return id;
          }
        }
      }
    }

    // Extra regex fallback for any other formatted YouTube URL
    try {
      final regExp = RegExp(
        r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?.*v=|shorts\/))([a-zA-Z0-9_-]{11})',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(trimmed);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  void _onPlayUrl() {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập hoặc dán link YouTube để phát!';
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Vui lòng nhập hoặc dán link YouTube để phát!'),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final videoId = _extractVideoId(text);
    if (videoId == null) {
      setState(() {
        _errorMessage = 'Link không hợp lệ! Vui lòng nhập link YouTube hợp lệ (ví dụ: https://youtube.com/watch?v=... hoặc https://youtu.be/... hoặc ID 11 ký tự).';
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Link không hợp lệ! Vui lòng kiểm tra lại link YouTube.'),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _loadVideoById(videoId, autoPlay: true);
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.play_circle_filled_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Đang phát video: $videoId')),
          ],
        ),
        backgroundColor: AppTheme.youtubeColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _urlController.text = text;
      _onPlayUrl();
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Bộ nhớ tạm trống hoặc không có nội dung văn bản!'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem Video YouTube'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Player Container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _controller != null
                    ? YoutubePlayer(
                        controller: _controller!,
                        aspectRatio: 16 / 9,
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: AppTheme.youtubeColor),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // Video Controls Bar
            if (_controller != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withAlpha(50)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      iconSize: 30,
                      color: AppTheme.youtubeColor,
                      tooltip: _isPlaying ? 'Tạm dừng' : 'Phát',
                      onPressed: () {
                        if (_isPlaying) {
                          _controller?.pauseVideo();
                        } else {
                          _controller?.playVideo();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                      tooltip: _isMuted ? 'Bật âm' : 'Tắt âm',
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                          if (_isMuted) {
                            _controller?.mute();
                          } else {
                            _controller?.unMute();
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay_10_rounded),
                      tooltip: 'Lùi 10s',
                      onPressed: () async {
                        final current = await _controller?.currentTime ?? 0;
                        _controller?.seekTo(seconds: (current - 10).clamp(0, 999999));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10_rounded),
                      tooltip: 'Tua 10s',
                      onPressed: () async {
                        final current = await _controller?.currentTime ?? 0;
                        _controller?.seekTo(seconds: current + 10);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen_rounded),
                      tooltip: 'Toàn màn hình',
                      onPressed: () {
                        _controller?.enterFullScreen();
                      },
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Link Input Card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppTheme.youtubeColor.withAlpha(40)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.link_rounded, color: AppTheme.youtubeColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Nhập link YouTube để xem',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Dán link hoặc ID video (ví dụ: youtu.be/...)',
                        hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
                        prefixIcon: const Icon(Icons.video_library_rounded, color: AppTheme.youtubeColor),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_urlController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                tooltip: 'Xóa link',
                                onPressed: () {
                                  setState(() {
                                    _urlController.clear();
                                    _errorMessage = null;
                                  });
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.paste_rounded, size: 20),
                              tooltip: 'Dán từ bộ nhớ tạm',
                              onPressed: _pasteFromClipboard,
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.youtubeColor, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _onPlayUrl(),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withAlpha(80)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.youtubeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _onPlayUrl,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Xem Video Ngay',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Quick Samples Section
            Row(
              children: [
                const Icon(Icons.video_collection_rounded, size: 20, color: AppTheme.youtubeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video Mẫu Xem Nhanh',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: YoutubeScreen.sampleVideos.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final video = YoutubeScreen.sampleVideos[index];
                final isCurrent = _currentVideoId == video['id'];
                return InkWell(
                  onTap: () {
                    _loadVideoById(video['id']!, autoPlay: true);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Đang phát: ${video['title']}')),
                          ],
                        ),
                        backgroundColor: AppTheme.youtubeColor,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isCurrent ? AppTheme.youtubeColor.withAlpha(20) : theme.cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCurrent ? AppTheme.youtubeColor : theme.dividerColor.withAlpha(40),
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isCurrent ? AppTheme.youtubeColor : AppTheme.youtubeColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCurrent ? Icons.play_arrow_rounded : Icons.video_file_rounded,
                            color: isCurrent ? Colors.white : AppTheme.youtubeColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video['title']!,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isCurrent ? AppTheme.youtubeColor : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${video['author']} • ID: ${video['id']}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
