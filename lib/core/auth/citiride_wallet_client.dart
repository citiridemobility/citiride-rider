import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'citiride_auth_service.dart';
import 'citiride_otp_client.dart';
import '../../features/wallet/presentation/wallet_banks.dart';

class CitirideWalletException implements Exception {
  const CitirideWalletException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CitirideFundingAccount {
  const CitirideFundingAccount({
    required this.accountName,
    required this.accountNumber,
    required this.bankName,
  });

  final String accountName;
  final String accountNumber;
  final String bankName;

  factory CitirideFundingAccount.fromJson(Map<String, dynamic>? json) {
    return CitirideFundingAccount(
      accountName: (json?['accountName'] as String?)?.trim() ?? '',
      accountNumber: (json?['accountNumber'] as String?)?.trim() ?? '',
      bankName: (json?['bankName'] as String?)?.trim() ?? '',
    );
  }
}

class CitirideWallet {
  const CitirideWallet({
    required this.userId,
    required this.availableBalance,
    required this.pendingBalance,
    required this.currency,
    required this.status,
    this.fundingAccount,
    this.testMode = false,
  });

  final String userId;
  final double availableBalance;
  final double pendingBalance;
  final String currency;
  final String status;
  final CitirideFundingAccount? fundingAccount;
  final bool testMode;

  factory CitirideWallet.fromJson(Map<String, dynamic> json) {
    final funding = json['fundingAccount'];
    return CitirideWallet(
      userId: (json['userId'] as String?) ?? '',
      availableBalance: (json['availableBalance'] as num?)?.toDouble() ?? 0,
      pendingBalance: (json['pendingBalance'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?) ?? 'NGN',
      status: (json['status'] as String?) ?? 'active',
      fundingAccount: funding is Map<String, dynamic>
          ? CitirideFundingAccount.fromJson(funding)
          : null,
      testMode: json['testMode'] == true,
    );
  }
}

class CitirideWalletTransaction {
  const CitirideWalletTransaction({
    required this.id,
    required this.reference,
    required this.type,
    required this.title,
    required this.amount,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String reference;
  final String type;
  final String title;
  final double amount;
  final String status;
  final DateTime? createdAt;

  factory CitirideWalletTransaction.fromJson(Map<String, dynamic> json) {
    return CitirideWalletTransaction(
      id: (json['id'] as String?) ?? '',
      reference: (json['reference'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Transaction',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? ''),
    );
  }
}

class CitirideWalletClient {
  CitirideWalletClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = _resolveBaseUrl(baseUrl);

  final http.Client _client;
  final String _baseUrl;

  static String _resolveBaseUrl(String? override) {
    final configured = (override ?? '').trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }
    return CitirideOtpClient.productionBaseUrl;
  }

  Future<CitirideWallet> ensureFundingAccount({
    required String email,
    String? fullName,
    String? phone,
  }) async {
    final body = await _post('/v1/wallet/ensure', {
      'email': email.trim().toLowerCase(),
      if (fullName != null && fullName.trim().isNotEmpty)
        'fullName': fullName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
    final walletJson = body['wallet'];
    if (walletJson is! Map<String, dynamic>) {
      throw const CitirideWalletException('Invalid wallet response');
    }
    return CitirideWallet.fromJson(walletJson);
  }

  Future<CitirideWallet> fetchWallet() async {
    final body = await _get('/v1/wallet/me');
    final walletJson = body['wallet'];
    if (walletJson is! Map<String, dynamic>) {
      throw const CitirideWalletException('Invalid wallet response');
    }
    return CitirideWallet.fromJson(walletJson);
  }

  Future<List<CitirideWalletTransaction>> fetchTransactions({
    int limit = 30,
  }) async {
    final body = await _get('/v1/wallet/me/transactions?limit=$limit');
    final list = body['transactions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map(
          (item) => CitirideWalletTransaction.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<List<WalletBank>> fetchBanks() async {
    final body = await _get('/v1/wallet/banks');
    final list = body['banks'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((item) => WalletBank.fromPaystackJson(Map<String, dynamic>.from(item)))
        .where((bank) => bank.paystackCode.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<CitirideWallet> requeryFunding() async {
    final body = await _post('/v1/wallet/funding/requery', {});
    final walletJson = body['wallet'];
    if (walletJson is! Map<String, dynamic>) {
      throw const CitirideWalletException('Invalid wallet response');
    }
    return CitirideWallet.fromJson(walletJson);
  }

  /// Test-mode only helper to simulate a successful DVA deposit.
  Future<CitirideWallet> simulateTestDeposit({double amount = 1000}) async {
    final body = await _post('/v1/wallet/test/credit', {'amount': amount});
    final walletJson = body['wallet'];
    if (walletJson is! Map<String, dynamic>) {
      throw const CitirideWalletException('Invalid wallet response');
    }
    return CitirideWallet.fromJson(walletJson);
  }

  Future<({String accountName, String accountNumber, String bankCode})>
  resolveBankAccount({
    required String accountNumber,
    required String bankCode,
  }) async {
    final body = await _post('/v1/wallet/bank/resolve', {
      'accountNumber': accountNumber,
      'bankCode': bankCode,
    });
    return (
      accountName: (body['accountName'] as String?)?.trim() ?? '',
      accountNumber: (body['accountNumber'] as String?)?.trim() ?? accountNumber,
      bankCode: (body['bankCode'] as String?)?.trim() ?? bankCode,
    );
  }

  Future<Map<String, dynamic>> withdraw({
    required double amount,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    String? accountName,
  }) async {
    return _post('/v1/wallet/withdraw', {
      'amount': amount,
      'bankCode': bankCode,
      'bankName': bankName,
      'accountNumber': accountNumber,
      if (accountName != null && accountName.trim().isNotEmpty)
        'accountName': accountName.trim(),
    });
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final headers = await _headers();
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _headers();
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (Firebase.apps.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final uid = user?.uid;
      if (uid != null && uid.isNotEmpty) {
        headers['X-User-Id'] = uid;
      }
      final email = user?.email;
      if (email != null && email.trim().isNotEmpty) {
        headers['X-User-Email'] = email.trim().toLowerCase();
      }
    }

    final fallbackUid = CitirideAuthService().currentUid;
    if (!headers.containsKey('X-User-Id') &&
        fallbackUid != null &&
        fallbackUid.isNotEmpty) {
      headers['X-User-Id'] = fallbackUid;
    }

    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw CitirideWalletException(
      (body['message'] as String?)?.trim().isNotEmpty == true
          ? body['message'] as String
          : 'Wallet request failed (${response.statusCode})',
      code: body['error'] as String?,
    );
  }
}
