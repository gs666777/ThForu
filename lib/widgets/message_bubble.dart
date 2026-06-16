import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import 'math_markdown.dart';
import 'streaming_cursor.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;
  final String? highlight;
  final bool isCurrentSearchMatch;
  final void Function(String content, String messageId)? onFollowUp;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final void Function(String messageId)? onScrollToMessage;
  final IconData? assistantIcon;
  final Color? assistantColor;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.highlight,
    this.isCurrentSearchMatch = false,
    this.onFollowUp,
    this.onDelete,
    this.onToggleFavorite,
    this.onScrollToMessage,
    this.assistantIcon,
    this.assistantColor,
  });

  bool get _isExpertResponse =>
      message.metadata != null &&
      message.metadata!['type'] == 'expert_response';

  void _showContextMenu(BuildContext context) {
    if (isStreaming) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.content.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制文本'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('引用回复'),
                subtitle: Text(
                  message.content.length > 200
                      ? '${message.content.substring(0, 200)}...'
                      : message.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final preview = message.content.length > 200
                      ? '${message.content.substring(0, 200)}...'
                      : message.content;
                  onFollowUp?.call(preview, message.id);
                },
              ),
            ],
            ListTile(
              leading: Icon(
                message.isFavorite ? Icons.star : Icons.star_border,
                color: message.isFavorite ? Colors.amber : null,
              ),
              title: Text(message.isFavorite ? '取消收藏' : '收藏'),
              onTap: () {
                Navigator.pop(ctx);
                onToggleFavorite?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openImageViewer(BuildContext context, String imagePath) {
    // Close keyboard before opening image viewer
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageViewerPage(imagePath: imagePath),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    final isMatch = highlight != null;

    if (_isExpertResponse) {
      return _buildExpertResponse(context, theme);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  assistantColor ?? theme.colorScheme.primaryContainer,
              child: Icon(
                  assistantIcon ?? Icons.smart_toy,
                  size: 18,
                  color: assistantColor != null
                      ? Colors.white
                      : theme.colorScheme.onPrimaryContainer),
            ),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showContextMenu(context),
              child: Container(
                constraints:
                    BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isCurrentSearchMatch
                      ? Colors.amber.withValues(alpha: 0.4)
                      : isMatch
                          ? Colors.amber.withValues(alpha: 0.15)
                          : isUser
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                  border: isCurrentSearchMatch
                      ? Border.all(color: Colors.amber, width: 2)
                      : null,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isUser
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isUser
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reply quote bar
                    if (message.metadata != null && message.metadata!['replyToId'] != null)
                      GestureDetector(
                        onTap: () {
                          final targetId = message.metadata!['replyToId'] as String;
                          onScrollToMessage?.call(targetId);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.reply, size: 14, color: theme.colorScheme.outline),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (message.metadata!['replyPreview'] as String? ?? '').length > 40
                                      ? '${(message.metadata!['replyPreview'] as String).substring(0, 40)}...'
                                      : (message.metadata!['replyPreview'] as String? ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (message.hasImages) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: message.imagePaths!.map((path) {
                          return GestureDetector(
                            onTap: () => _openImageViewer(context, path),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (message.content.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (message.hasFile) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.insert_drive_file,
                                size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                message.fileName ?? '文件',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (message.content.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (isUser)
                      Text(message.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer))
                    else if (isStreaming && message.content.isEmpty)
                      _TypingIndicator(theme: theme)
                    else if (isStreaming)
                      _StreamingContent(
                        content: message.content,
                        theme: theme,
                      )
                    else
                      RepaintBoundary(
                        child: MathMarkdown(
                          data: message.content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface),
                            code: theme.textTheme.bodySmall?.copyWith(
                              backgroundColor: theme.colorScheme.surface,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    if (isStreaming && message.content.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _BlinkingCursor(theme: theme),
                    ],
                    if (message.isFavorite) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 13, color: Colors.amber.shade600),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildExpertResponse(BuildContext context, ThemeData theme) {
    final providerName =
        message.metadata?['providerName'] as String? ?? '未知来源';
    final isEmpty = message.content.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 36),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showContextMenu(context),
              child: _ExpertResponseCard(
                providerName: providerName,
                content: message.content,
                isEmpty: isEmpty,
                isStreaming: isStreaming,
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns the offset of the first unclosed LaTeX delimiter, or -1 if all closed.
int _latexSplitOffset(String text) {
  int i = 0;
  while (i < text.length) {
    if (i + 1 < text.length && text[i] == r'$' && text[i + 1] == r'$') {
      final end = text.indexOf(r'$$', i + 2);
      if (end < 0) return i;
      i = end + 2;
    } else if (i + 1 < text.length && text[i] == '\\' && text[i + 1] == '[') {
      final end = text.indexOf('\\]', i + 2);
      if (end < 0) return i;
      i = end + 2;
    } else if (text[i] == r'$') {
      final end = text.indexOf(r'$', i + 1);
      if (end < 0) return i;
      i = end + 1;
    } else {
      i++;
    }
  }
  return -1;
}

/// Renders streaming content: complete formulas with MathMarkdown,
/// incomplete tail with plain Text.
class _StreamingContent extends StatelessWidget {
  final String content;
  final ThemeData theme;

  const _StreamingContent({
    required this.content,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final splitAt = _latexSplitOffset(content);

    final mdStyle = MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface),
      code: theme.textTheme.bodySmall?.copyWith(
        backgroundColor: theme.colorScheme.surface,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    if (splitAt < 0) {
      return RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MathMarkdown(
              data: content,
              selectable: true,
              styleSheet: mdStyle,
            ),
            const StreamingCursor(),
          ],
        ),
      );
    }

    final completePart = content.substring(0, splitAt);
    final tailPart = content.substring(splitAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (completePart.isNotEmpty)
          RepaintBoundary(
            child: MathMarkdown(
              data: completePart,
              selectable: true,
              styleSheet: mdStyle,
            ),
          ),
        Text.rich(TextSpan(children: [
          TextSpan(text: tailPart),
          const WidgetSpan(child: StreamingCursor()),
        ], style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface))),
      ],
    );
  }
}

class _ExpertResponseCard extends StatefulWidget {
  final String providerName;
  final String content;
  final bool isEmpty;
  final bool isStreaming;
  final ThemeData theme;

  const _ExpertResponseCard({
    required this.providerName,
    required this.content,
    required this.isEmpty,
    required this.isStreaming,
    required this.theme,
  });

  @override
  State<_ExpertResponseCard> createState() => _ExpertResponseCardState();
}

class _ExpertResponseCardState extends State<_ExpertResponseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: Colors.purple.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology,
                      size: 14, color: Colors.purple.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    widget.providerName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.isEmpty && widget.isStreaming) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.content.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && widget.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 8),
              child: MathMarkdown(
                data: widget.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                  ),
                  code: theme.textTheme.bodySmall?.copyWith(
                    backgroundColor: theme.colorScheme.surface,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final ThemeData theme;
  const _TypingIndicator({required this.theme});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final delay = i * 0.2;
        return ListenableBuilder(
          listenable: _controller,
          builder: (_, child) {
            final t = (_controller.value - delay) % 1.0;
            final v = t < 0 ? 0.0 : (t < 0.5 ? t / 0.5 : (1.0 - t) / 0.5);
            final scale = 0.4 + 0.6 * v.clamp(0.0, 1.0);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  final ThemeData theme;
  const _BlinkingCursor({required this.theme});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 16,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fullscreen image viewer with pinch-to-zoom
// ---------------------------------------------------------------------------

class _ImageViewerPage extends StatelessWidget {
  final String imagePath;
  const _ImageViewerPage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('无法加载图片', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }
}
