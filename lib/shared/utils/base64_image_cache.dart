import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Decodes base64 image strings once and reuses the bytes.
///
/// Widgets used to call base64Decode() inside build(), so every rebuild
/// (scrolling a feed, a setState anywhere above) re-decoded the same
/// ~100 KB string and handed Image.memory a brand-new byte list — wasted
/// work, and a visible flicker because the image cache keys on the bytes.
/// A small LRU keeps memory bounded.
class Base64ImageCache {
  Base64ImageCache._();

  static const int _maxEntries = 40;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// Returns the decoded bytes, or null for null/empty/corrupt input.
  static Uint8List? decode(String? base64) {
    if (base64 == null || base64.isEmpty) return null;

    final hit = _cache.remove(base64);
    if (hit != null) {
      _cache[base64] = hit; // re-insert as most recently used
      return hit;
    }

    try {
      final bytes = base64Decode(base64);
      _cache[base64] = bytes;
      if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
      return bytes;
    } catch (_) {
      return null; // corrupted data — callers fall back gracefully
    }
  }
}
