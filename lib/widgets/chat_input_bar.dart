import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai_service.dart';
import '../state/providers.dart';
import 'image_preview_sheet.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  final Future<void> Function({
    required String text,
    List<String>? imagePaths,
    String? filePath,
    String? fileName,
  }) onSend;
  final VoidCallback? onMessageSent;
  final bool supportsVision;
  final bool supportsFile;
  final String? hintText;
  final String? prefillText;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onMessageSent,
    this.supportsVision = false,
    this.supportsFile = false,
    this.hintText,
    this.prefillText,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _selectedImages = [];
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isRecording = false;
  bool _isTranscribing = false;

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefillText != null &&
        widget.prefillText != oldWidget.prefillText) {
      _textController.text = widget.prefillText!;
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedFilePath == null) return;

    widget.onSend(
      text: text,
      imagePaths:
          _selectedImages.isNotEmpty ? List.from(_selectedImages) : null,
      filePath: _selectedFilePath,
      fileName: _selectedFileName,
    );

    _textController.clear();
    setState(() {
      _selectedImages.clear();
      _selectedFilePath = null;
      _selectedFileName = null;
    });
    widget.onMessageSent?.call();
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final paths = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();
        if (paths.isNotEmpty) {
          setState(() => _selectedImages.addAll(paths));
        }
      }
    } catch (_) {}
  }

  Future<void> _takePhoto() async {
    final imageService = ref.read(imageServiceProvider);
    final path = await imageService.pickFromCamera();
    if (path != null) {
      setState(() => _selectedImages.add(path));
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          setState(() {
            _selectedFilePath = file.path;
            _selectedFileName = file.name;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    final audioService = ref.read(audioServiceProvider);
    final hasPermission = await audioService.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要录音权限')),
        );
      }
      return;
    }
    setState(() => _isRecording = true);
    await audioService.startRecording();
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);

    final audioService = ref.read(audioServiceProvider);
    final path = await audioService.stopRecording();
    if (path == null) return;

    setState(() => _isTranscribing = true);

    // Use the first available provider from the list for transcription
    final providers = ref.read(providerListProvider);
    if (providers.isEmpty) {
      setState(() => _isTranscribing = false);
      return;
    }
    final aiService = AiService(providers.first);
    try {
      final text = await aiService.transcribeAudio(path);
      _textController.text += text;
    } on AiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音转录失败: $e')),
        );
      }
    } finally {
      setState(() => _isTranscribing = false);
    }
  }

  void _showImagePreview() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ImagePreviewSheet(
        images: _selectedImages,
        onRemove: (index) {
          setState(() => _selectedImages.removeAt(index));
          if (_selectedImages.isEmpty) Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedImages.isNotEmpty)
              GestureDetector(
                onTap: _showImagePreview,
                child: Container(
                  height: 72,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.image, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('已选择 ${_selectedImages.length} 张图片',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                      const Spacer(),
                      Text('点击预览', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            if (_selectedFilePath != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.attach_file,
                      color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selectedFileName ?? '文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _selectedFilePath = null;
                      _selectedFileName = null;
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.supportsFile)
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: '发送文件',
                  onPressed: _pickFile,
                ),
              if (widget.supportsVision)
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: '发送图片',
                  onPressed: () => _showImageSourceSheet(),
                ),
              IconButton(
                icon: _isTranscribing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.red : null,
                      ),
                tooltip: '语音输入',
                onPressed: _isRecording ? _stopRecording : _startRecording,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _isRecording
                        ? '正在录音...'
                        : widget.hintText ?? '输入消息...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                  ),
                  enabled: !_isRecording,
                ),
              ),
              IconButton(
                icon: Icon(Icons.send_rounded,
                    color: theme.colorScheme.primary),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages();
              },
            ),
          ],
        ),
      ),
    );
  }
}
