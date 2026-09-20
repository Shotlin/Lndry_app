import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/api/repositories/api_customer_repository.dart';
import 'package:lndry/core/network/api_exception.dart';
import 'package:lndry/core/network/friendly_error.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for the backend that records what was sent.
class _Backend implements HttpClientAdapter {
  _Backend(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );

Future<ApiCustomerRepository> _repo(_Backend backend) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = backend;
  return ApiCustomerRepository(dio: dio, storage: StorageService(prefs: prefs));
}

const _ok = {
  'success': true,
  'message': 'Ready to reorder',
  'data': {
    'vendorId': 'v1',
    'vendorName': 'Shotlin Laundry',
    'itemCount': 6,
    'items': [
      {'serviceId': 'g1', 'name': 'Wash & Fold', 'unit': 'kg', 'quantity': 2, 'ratePaise': 8000},
      {'serviceId': 'g2', 'name': 'Shirt', 'unit': 'piece', 'quantity': 4, 'ratePaise': 9000},
    ],
    'unavailable': [
      {'name': 'Saree', 'reason': 'No longer offered by this laundry'},
    ],
  },
};

void main() {
  test('reorder sends a real (empty) JSON body — the old request had none and got a 400', () async {
    final backend = _Backend((_) => _json(200, _ok));
    final repo = await _repo(backend);
    await repo.reorder('order-1');
    expect(backend.last!.method, 'POST');
    expect(backend.last!.path, contains('/orders/order-1/reorder'));
    expect(backend.last!.data, isA<Map>(), reason: 'a JSON body is sent, so the request is not empty');
  });

  test('reorder builds the cart from what the backend says is available today', () async {
    final repo = await _repo(_Backend((_) => _json(200, _ok)));
    final result = await repo.reorder('order-1');
    final cart = await repo.getCart();
    expect(cart.items.map((i) => [i.serviceId, i.vendorId, i.quantity]), [
      ['g1', 'v1', 2],
      ['g2', 'v1', 4],
    ]);
    expect(result.itemCount, 6);
    expect(result.message, '6 items added to your cart. Not available right now: Saree.');
    expect(result.warnings, ['Saree']);
  });

  test('reordering twice does not double the quantities', () async {
    final repo = await _repo(_Backend((_) => _json(200, _ok)));
    await repo.reorder('order-1');
    await repo.reorder('order-1');
    final cart = await repo.getCart();
    expect(cart.items.map((i) => i.quantity), [2, 4]);
  });

  test('the selection Checkout reads becomes exactly this reorder — leftovers are dropped', () async {
    final repo = await _repo(_Backend((_) => _json(200, _ok)));
    await repo.addToCart(serviceId: 'other', vendorId: 'v9', quantity: 3); // another laundry
    await repo.addToCart(serviceId: 'stale', vendorId: 'v1', quantity: 5); // same laundry, left from earlier browsing
    await repo.reorder('order-1');
    final cart = await repo.getCart();
    expect(cart.items.map((i) => i.serviceId), ['g1', 'g2']);
    expect(cart.items.every((i) => i.vendorId == 'v1'), isTrue);
  });

  test('a laundry that is unavailable gives a plain sentence, never Dio/HTTP text', () async {
    final backend = _Backend((_) => _json(409, {
          'success': false,
          'message': "This laundry isn't accepting orders right now.",
          'code': 'REORDER_VENDOR_UNAVAILABLE',
        }));
    final repo = await _repo(backend);
    Object? caught;
    try {
      await repo.reorder('order-1');
    } catch (e) {
      caught = e;
    }
    expect(caught, isNotNull);
    // The bare repository (no app interceptor) still surfaces a DioException; what matters is what the person sees.
    final shown = friendlyError(caught is DioException && caught.response?.data is Map
        ? ApiException(message: (caught.response!.data as Map)['message'] as String, statusCode: 409)
        : caught);
    expect(shown, "This laundry isn't accepting orders right now.");
  });

  group('friendlyError', () {
    test('a 400 with the old empty-body text, a 502 and a dropped connection all become one sentence', () {
      expect(
        friendlyError(const ApiException(message: "Body cannot be empty when content-type is set to 'application/json'", statusCode: 400, code: 'FST_ERR_CTP_EMPTY_JSON_BODY')),
        'Something went wrong. Please try again.',
      );
      expect(friendlyError(const ApiException(message: 'Bad Gateway', statusCode: 502)), 'The server is busy right now. Please try again in a moment.');
      expect(
        friendlyError(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError)),
        contains("Couldn't reach the server"),
      );
      expect(friendlyError(StateError('boom')), 'Something went wrong. Please try again.');
    });

    test('a message written for people is kept', () {
      const msg = 'None of the items from this order are available right now.';
      expect(friendlyError(const ApiException(message: msg, statusCode: 409)), msg);
    });
  });
}
