import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Resolves an image string to the right [ImageProvider], transparently
/// supporting BOTH:
///   • inline `data:image/...;base64,...` URIs (how this app stores images so it
///     works without Firebase Storage / the Blaze plan), and
///   • regular `http(s)` download URLs (cached).
/// Returns null for empty/invalid input so callers can render a fallback.
ImageProvider? appImageProvider(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma == -1) return null;
    try {
      return MemoryImage(base64Decode(url.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }
  return CachedNetworkImageProvider(url);
}

/// True when [url] is a non-empty image reference we can render.
bool hasImage(String? url) => url != null && url.isNotEmpty;
