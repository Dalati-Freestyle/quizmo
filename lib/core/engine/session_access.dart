import 'dart:convert';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:crypto/crypto.dart';

import '../models/json.dart';

enum AdmissionDecision { waiting, approved, rejected }

final class Admission {
  const Admission(this.name, this.decision);
  final String name;
  final AdmissionDecision decision;
}

final class SessionAccessState {
  const SessionAccessState({
    this.codeHash,
    this.locked = false,
    this.requireApproval = false,
    this.allowSpectators = true,
    this.bannedPlayerIds = const {},
    this.requests = const {},
  });

  final String? codeHash;
  final bool locked;
  final bool requireApproval;
  final bool allowSpectators;
  final Set<String> bannedPlayerIds;
  final Map<String, Admission> requests;

  JsonMap toJson() => {
    'codeHash': codeHash,
    'locked': locked,
    'requireApproval': requireApproval,
    'allowSpectators': allowSpectators,
    'bannedPlayerIds': bannedPlayerIds.toList(),
  };

  factory SessionAccessState.fromJson(JsonMap json) {
    final hash = json.readStringOrNull('codeHash');
    final ids = json['bannedPlayerIds'];
    if (json.length != 5 ||
        !json.containsKey('codeHash') ||
        json['locked'] is! bool ||
        json['requireApproval'] is! bool ||
        json['allowSpectators'] is! bool ||
        hash != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        ids is! List ||
        ids.any((id) => id is! String)) {
      throw const JsonContractException('Invalid session access settings.');
    }
    return SessionAccessState(
      codeHash: hash,
      locked: json.readBool('locked'),
      requireApproval: json.readBool('requireApproval'),
      allowSpectators: json.readBool('allowSpectators'),
      bannedPlayerIds: ids.cast<String>().toSet(),
    );
  }
}

/// Session policy is host-owned, never accepted from a client message.
final class SessionAccess extends Cubit<SessionAccessState> {
  SessionAccess([super.initialState = const SessionAccessState()]);

  static String digestCredential(String code) =>
      sha256.convert(utf8.encode(code)).toString();
  final Map<String, String> _readCredentials = {};

  bool get requiresCredential =>
      state.codeHash != null ||
      state.locked ||
      state.requireApproval ||
      !state.allowSpectators;

  String issueReadCredential(String connectionId) {
    final token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _readCredentials[connectionId] = digestCredential(token);
    return token;
  }

  void revokeReadCredential(String connectionId) =>
      _readCredentials.remove(connectionId);

  bool mayRead(String? token) =>
      !requiresCredential ||
      token != null &&
          token.length <= 128 &&
          _readCredentials.containsValue(digestCredential(token));

  void configure({
    String? code,
    bool? locked,
    bool? requireApproval,
    bool? allowSpectators,
  }) {
    if (code != null &&
        code.isNotEmpty &&
        (code.length < 6 || code.length > 64)) {
      throw ArgumentError('Use a join code with 6 to 64 characters.');
    }
    emit(
      SessionAccessState(
        codeHash: code == null
            ? state.codeHash
            : code.isEmpty
            ? null
            : digestCredential(code),
        locked: locked ?? state.locked,
        requireApproval: requireApproval ?? state.requireApproval,
        allowSpectators: allowSpectators ?? state.allowSpectators,
        bannedPlayerIds: state.bannedPlayerIds,
        requests: state.requests,
      ),
    );
  }

  void request(String id, String name) => _requests({
    ...state.requests,
    id: Admission(name, AdmissionDecision.waiting),
  });

  void decide(String id, {required bool approve}) {
    final request = state.requests[id];
    if (request == null) return;
    _requests({
      ...state.requests,
      id: Admission(
        request.name,
        approve ? AdmissionDecision.approved : AdmissionDecision.rejected,
      ),
    });
  }

  void forget(String id) {
    if (!state.requests.containsKey(id)) return;
    _requests({...state.requests}..remove(id));
  }

  void ban(String playerId) => emit(
    SessionAccessState(
      codeHash: state.codeHash,
      locked: state.locked,
      requireApproval: state.requireApproval,
      allowSpectators: state.allowSpectators,
      bannedPlayerIds: {...state.bannedPlayerIds, playerId},
      requests: state.requests,
    ),
  );

  void _requests(Map<String, Admission> requests) => emit(
    SessionAccessState(
      codeHash: state.codeHash,
      locked: state.locked,
      requireApproval: state.requireApproval,
      allowSpectators: state.allowSpectators,
      bannedPlayerIds: state.bannedPlayerIds,
      requests: Map.unmodifiable(requests),
    ),
  );
}
