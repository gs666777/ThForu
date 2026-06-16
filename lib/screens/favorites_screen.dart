import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> with RouteAware {
  List<Map<String, dynamic>>? _favorites;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    final dao = ref.read(messageDaoProvider);
    final list = await dao.getFavorites();
    if (mounted) setState(() => _favorites = list);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: _favorites == null
          ? const Center(child: CircularProgressIndicator())
          : _favorites!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('还没有收藏的消息',
                          style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.outline)),
                      const SizedBox(height: 8),
                      Text('长按消息可以收藏',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _favorites!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _favorites![index];
                    final content = item['content'] as String;
                    final title =
                        item['conversation_title'] as String? ?? 'Chat';
                    final convId = item['conversation_id'] as String;
                    final msgId = item['id'] as String;

                    return ListTile(
                      leading: const Icon(Icons.star,
                          color: Colors.amber, size: 20),
                      title: Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary),
                      ),
                      subtitle: Text(
                        content.length > 80
                            ? '${content.substring(0, 80)}...'
                            : content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.star, color: Colors.amber),
                        tooltip: '取消收藏',
                        onPressed: () async {
                          final dao = ref.read(messageDaoProvider);
                          await dao.toggleFavorite(convId, msgId);
                          setState(() {
                            _favorites?.removeWhere((e) => e['id'] == msgId);
                          });
                        },
                      ),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/chat',
                          arguments: convId,
                        );
                      },
                    );
                  },
                ),
    );
  }
}
