import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:saver_gallery/saver_gallery.dart';

/// Renders SVG as a bitmap thumbnail in the chat bubble.
/// Tap to open fullscreen with pinch-to-zoom.
class SvgBlock extends StatefulWidget {
  final String svgString;
  const SvgBlock({super.key, required this.svgString});

  @override
  State<SvgBlock> createState() => _SvgBlockState();
}

class _SvgBlockState extends State<SvgBlock> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      final pictureInfo = await vg.loadPicture(
        SvgStringLoader(widget.svgString),
        null,
      );
      final svgSize = pictureInfo.size;
      if (svgSize.width <= 0 || svgSize.height <= 0) {
        pictureInfo.picture.dispose();
        if (mounted) setState(() => _failed = true);
        return;
      }

      // Thumbnail: max 280px wide, maintain aspect ratio
      final maxW = 280.0;
      final scale = maxW / svgSize.width;
      final w = (svgSize.width * scale).round();
      final h = (svgSize.height * scale).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale, scale);
      canvas.drawPicture(pictureInfo.picture);
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      pictureInfo.picture.dispose();
      picture.dispose();
      if (mounted) setState(() => _image = img);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SvgViewer(svgString: widget.svgString),
      ),
    );
  }

  Future<void> _downloadSvg() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, 'svg_$timestamp.svg'));
      await file.writeAsString(widget.svgString);

      final bytes = await file.readAsBytes();
      final result = await SaverGallery.saveImage(
        bytes,
        quality: 100,
        fileName: 'svg_$timestamp.svg',
        skipIfExists: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isSuccess ? '已保存到相册' : '保存失败'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, size: 13,
                  color: _failed ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(width: 5),
              Text(_failed ? 'SVG (解析失败)' : 'SVG',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: _failed ? theme.colorScheme.error : theme.colorScheme.primary)),
              if (_image != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _downloadSvg,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download, size: 14,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text('下载', style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _openFullscreen,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, size: 14,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text('放大', style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            if (_image != null)
              GestureDetector(
                onTap: _openFullscreen,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RawImage(image: _image),
                  ),
                ),
              )
            else if (_failed)
              _sourceView(theme)
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sourceView(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          widget.svgString,
          maxLines: 15,
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

/// Fullscreen SVG viewer — renders at screen resolution, pinch-to-zoom.
class _SvgViewer extends StatefulWidget {
  final String svgString;
  const _SvgViewer({required this.svgString});

  @override
  State<_SvgViewer> createState() => _SvgViewerState();
}

class _SvgViewerState extends State<_SvgViewer> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      final pictureInfo = await vg.loadPicture(
        SvgStringLoader(widget.svgString),
        null,
      );
      final svgSize = pictureInfo.size;
      if (svgSize.width <= 0 || svgSize.height <= 0) {
        pictureInfo.picture.dispose();
        if (mounted) setState(() => _failed = true);
        return;
      }
      // Render at 2x screen width for sharp zoom
      final screenW = MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first)
          .size
          .width;
      final maxW = screenW * 2;
      final scale = maxW / svgSize.width;
      final w = (svgSize.width * scale).round();
      final h = (svgSize.height * scale).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale, scale);
      canvas.drawPicture(pictureInfo.picture);
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      pictureInfo.picture.dispose();
      picture.dispose();
      if (mounted) setState(() => _image = img);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('SVG'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _image != null
          ? InteractiveViewer(
              maxScale: 20.0,
              minScale: 0.1,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _image!.width.toDouble(),
                    height: _image!.height.toDouble(),
                    child: RawImage(image: _image),
                  ),
                ),
              ),
            )
          : _failed
              ? const Center(child: Text('SVG 解析失败'))
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
