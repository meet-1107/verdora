import 'package:flutter/material.dart';

/// A scroll-friendly list for large datasets. It renders an initial window of
/// [pageSize] items and reveals more (with a small loader) as the user scrolls
/// near the bottom — so a screen never tries to lay out thousands of rows at
/// once. Works on top of an already-loaded list (the stream still provides the
/// data); it keeps scrolling smooth and shows the "loading more…" affordance
/// users expect on big catalogs/orders.
class AppLazyListView<T> extends StatefulWidget {
  const AppLazyListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.separatorHeight = 8,
    this.padding = const EdgeInsets.all(16),
    this.pageSize = 20,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double separatorHeight;
  final EdgeInsets padding;
  final int pageSize;

  @override
  State<AppLazyListView<T>> createState() => _AppLazyListViewState<T>();
}

class _AppLazyListViewState<T> extends State<AppLazyListView<T>> {
  final _controller = ScrollController();
  late int _visible = widget.pageSize;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AppLazyListView<T> old) {
    super.didUpdateWidget(old);
    // Keep the window valid if the underlying list shrank.
    if (_visible > widget.items.length && widget.items.length > widget.pageSize) {
      _visible = widget.items.length;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore) return;
    if (_visible >= widget.items.length) return;
    if (_controller.position.pixels >=
        _controller.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    // Brief pause so the loader is visible, then reveal the next page.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _visible = (_visible + widget.pageSize).clamp(0, widget.items.length);
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final shown = _visible.clamp(0, total);
    final hasMore = shown < total;

    return ListView.separated(
      controller: _controller,
      padding: widget.padding,
      itemCount: shown + (hasMore ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: widget.separatorHeight),
      itemBuilder: (context, i) {
        if (i >= shown) {
          // Trailing loader row.
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return widget.itemBuilder(context, widget.items[i], i);
      },
    );
  }
}
