import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Turns anything thrown while talking to the backend into ONE short sentence
/// that is safe to show a customer.
///
/// Customers never see `DioException`, HTTP status text, stack traces or class
/// names. A message the backend wrote for people (e.g. "This laundry isn't
/// accepting orders right now.") is passed through; anything technical — a
/// 5xx, a gateway error, a timeout, a dropped connection, an unknown
/// exception — becomes a plain sentence instead.
String friendlyError(Object? error) {
  final api = _apiExceptionOf(error);
  if (api != null) {
    if (api.code == 'TIMEOUT') return _timeout;
    final status = api.statusCode;
    if (status == null) return _network;
    if (status >= 500) return _serverBusy;
    return _readable(api.message) ?? _generic;
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _timeout;
      case DioExceptionType.connectionError:
        return _network;
      default:
        break;
    }
    final status = error.response?.statusCode;
    if (status != null && status >= 500) return _serverBusy;
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      final message = _readable(data['message'] as String);
      if (message != null) return message;
    }
    return _generic;
  }

  // A programming Error (StateError, TypeError, …) is never meant for people.
  if (error is Error) return _generic;

  // Some code throws Exception('A sentence meant for people'); keep those,
  // drop the "Exception: " prefix, and hide anything that looks technical.
  final text = error?.toString() ?? '';
  final stripped = text.startsWith('Exception: ') ? text.substring(11) : text;
  return _readable(stripped) ?? _generic;
}

const _generic = 'Something went wrong. Please try again.';
const _network = "Couldn't reach the server. Check your internet connection and try again.";
const _timeout = 'The request took too long. Please try again.';
const _serverBusy = 'The server is busy right now. Please try again in a moment.';

ApiException? _apiExceptionOf(Object? error) {
  if (error is ApiException) return error;
  if (error is DioException && error.error is ApiException) {
    return error.error as ApiException;
  }
  return null;
}

/// The message if it is a short sentence a person can read; null if it looks
/// like framework/HTTP output.
String? _readable(String? raw) {
  final message = raw?.trim() ?? '';
  if (message.isEmpty || message.length > 160) return null;
  const technical = [
    'DioException',
    'DioError',
    'RequestOptions',
    'ApiException',
    'status code',
    'Http status',
    'Exception',
    'Error:',
    'Instance of',
    'Null check',
    "type '",
    'package:',
    'dart:',
    'developer.mozilla.org',
    'content-type',
    'application/json',
    'Body cannot',
    'Unhandled',
    'StackTrace',
    'FST_ERR',
  ];
  for (final marker in technical) {
    if (message.contains(marker)) return null;
  }
  if (message == 'Unknown error' || message == 'Request failed') return null;
  return message;
}
