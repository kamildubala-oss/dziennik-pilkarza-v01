import 'package:flutter/foundation.dart';

/// Prosty odpowiednik `useQuery` z react-query:
/// przechowuje dane, stan ładowania i pozwala je odświeżyć.
class Resource<T> {
  Resource(this._fetch, this._notify);

  final Future<T> Function() _fetch;
  final VoidCallback _notify;

  T? data;
  Object? error;
  bool isLoading = true;
  bool isRefetching = false;
  bool _disposed = false;

  Future<void> refetch() async {
    if (_disposed) return;
    if (!isLoading) {
      isRefetching = true;
      _notify();
    }
    try {
      data = await _fetch();
      error = null;
    } catch (e) {
      error = e;
    }
    isLoading = false;
    isRefetching = false;
    if (!_disposed) _notify();
  }

  void dispose() {
    _disposed = true;
  }
}
