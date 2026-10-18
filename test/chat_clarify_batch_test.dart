import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';

/// Mimics the production transport's batch-clarify behaviour: locking one
/// answer emits `clarify.remaining` before the response future completes
/// (see `DesktopGatewayClient.respondToClarify`).
class _BatchClarifySession implements GatewayTurnApplicationSession {
  _BatchClarifySession(this.emit);

  final void Function(StreamEvent event) emit;
  final Map<String, Set<String>> _open = {};
  final List<({String requestId, String? questionId, String answer})> answers =
      [];

  void openBatch(String requestId, List<String> qids) {
    _open[requestId] = qids.toSet();
  }

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    answers.add((requestId: requestId, questionId: questionId, answer: answer));
    final remaining = _open[requestId];
    if (remaining != null && questionId != null) {
      remaining.remove(questionId);
      emit(
        StreamEvent(
          type: 'clarify.remaining',
          data: {'id': requestId, 'remaining': remaining.toList()},
        ),
      );
    }
    return true;
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) => Object();

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}

  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) => Object();

  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {}

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) => false;

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async => false;

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async => false;

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async => false;

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async => const [];

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

const _sessionId = 'batch-clarify-session';

Future<(_BatchClarifySession, TestDesktopAsyncEventHook)> _pumpChat(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({'verbose_mode': false});
  final hook = TestDesktopAsyncEventHook();
  final session = _BatchClarifySession((event) => hook.handler?.call(event));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'batch-clarify-fixture',
          label: 'Batch clarify fixture',
          host: 'fixture.invalid',
          port: 8000,
          apiKey: 'fixture-key',
          desktopGatewayUrl: 'http://127.0.0.1:9',
        ),
        session: const Session(
          id: _sessionId,
          title: 'Chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testDesktopAsyncEventHook: hook,
        testTurnApplicationSession: session,
        testApiClient: ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'fixture-key',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'data': []}), 200),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  return (session, hook);
}

/// `tester.pump()` only builds a frame when one is already scheduled, so
/// post-frame work (the clarify queue opens its dialog from a post-frame
/// callback) needs an explicit frame request.
Future<void> _pumpFrames(WidgetTester tester, [Duration? step]) async {
  for (var i = 0; i < 3; i++) {
    tester.binding.scheduleFrame();
    await tester.pump(step);
  }
}

void _deliverBatchQuestion(TestDesktopAsyncEventHook hook) {
  hook.handler?.call(
    StreamEvent(
      type: 'clarify.request',
      data: {
        'request_id': 'r1',
        'questions': [
          {
            'qid': 'q1',
            'question': 'First question?',
            'choices': ['One A', 'One B'],
          },
          {
            'qid': 'q2',
            'question': 'Second question?',
            'choices': ['Two A', 'Two B'],
          },
        ],
      },
    ),
  );
}

void main() {
  testWidgets('answers every question of a batch clarify request', (
    tester,
  ) async {
    final (session, hook) = await _pumpChat(tester);
    session.openBatch('r1', ['q1', 'q2']);

    _deliverBatchQuestion(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    // The first question is presented on its own card.
    expect(find.text('First question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clarify-choice-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    expect(session.answers, hasLength(1));
    expect(session.answers.single.questionId, 'q1');
    expect(session.answers.single.answer, 'One B');

    // The chat must survive the answer: a second route pop here navigates the
    // user out of the conversation and strands the remaining question.
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Second question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clarify-choice-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    expect(session.answers, hasLength(2));
    expect(session.answers.last.questionId, 'q2');
    expect(session.answers.last.answer, 'Two A');
    expect(find.text('Second question?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
