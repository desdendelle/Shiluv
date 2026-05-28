import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'src/json_decoding.dart';
import 'src/upload_validation.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

void main() {
  runApp(const ProviderScope(child: ShiluvApp()));
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/schedule',
              builder: (context, state) => const ScheduleScreen()),
          GoRoute(
              path: '/manager',
              builder: (context, state) => const ManagerScreen()),
          GoRoute(
              path: '/roster',
              builder: (context, state) => const RosterScreen()),
          GoRoute(
              path: '/alerts',
              builder: (context, state) => const AlertsScreen()),
        ],
      ),
    ],
  );
});

class ShiluvApp extends ConsumerWidget {
  const ShiluvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('he'),
      supportedLocales: const [Locale('he')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF165B5A),
          primary: const Color(0xFF165B5A),
          secondary: const Color(0xFFC28738),
          surface: const Color(0xFFFFFCF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        fontFamily: 'Arial',
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFFFFFCF7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class AuthState {
  const AuthState({this.user, this.client, this.error, this.isLoading = false});

  final SessionUser? user;
  final ApiClient? client;
  final String? error;
  final bool isLoading;

  bool get isAuthenticated => user != null && client != null;

  AuthState copyWith({
    SessionUser? user,
    ApiClient? client,
    String? error,
    bool? isLoading,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : user ?? this.user,
      client: clearUser ? null : client ?? this.client,
      error: clearError ? null : error ?? this.error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final client = ApiClient(username: username, password: password);
    try {
      final user = await client.session();
      state = AuthState(user: user, client: client);
    } on ApiException catch (error) {
      state = AuthState(error: error.message);
    } on Object {
      state = const AuthState(error: 'לא ניתן להתחבר לשרת');
    }
  }

  void logout() {
    state = const AuthState();
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;
}

class ApiClient {
  ApiClient({required this.username, required this.password});

  final String username;
  final String password;

  Map<String, String> get _headers {
    final token = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $token',
      'Content-Type': 'application/json',
    };
  }

  Future<SessionUser> session() async {
    final body = await _get('/api/v1/session');
    return SessionUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<ClientConfig> config() async {
    final body = await _get('/api/v1/config', authenticated: false);
    return ClientConfig.fromJson(body);
  }

  Future<ProgramatsiaStatus> programatsia(String weekStart) async {
    final body = await _get('/api/v1/weeks/$weekStart/programatsia');
    return ProgramatsiaStatus.fromJson(body);
  }

  Future<List<Shift>> schedule(String weekStart) async {
    final body =
        await _get('/api/v1/weeks/$weekStart/schedule', allowConflict: true);
    final items = body['shifts'] as List<dynamic>? ?? [];
    return items
        .map((item) => Shift.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ShiftExclusion>> exclusions(String weekStart) async {
    final body = await _get('/api/v1/weeks/$weekStart/shift-exclusions');
    final items = body['exclusions'] as List<dynamic>? ?? [];
    return items
        .map((item) => ShiftExclusion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ProgramatsiaStatus> uploadProgramatsia({
    required String weekStart,
    required web.File file,
    required Uint8List bytes,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/weeks/$weekStart/programatsia');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = _headers['Authorization']!;
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    final response = await request.send();
    final body = decodeJsonObjectFromBytes(await response.stream.toBytes());
    if (response.statusCode >= 400) {
      throw ApiException(_errorMessage(body));
    }
    return ProgramatsiaStatus.fromJson(body);
  }

  Future<void> createExclusion({
    required String weekStart,
    required String shiftId,
    required String workerId,
  }) async {
    await _post(
      '/api/v1/weeks/$weekStart/shift-exclusions',
      {
        'shift_id': shiftId,
        'worker_id': workerId,
      },
    );
  }

  Future<DutyRoster> roster(String weekStart) async {
    final body = await _get('/api/v1/weeks/$weekStart/roster');
    return DutyRoster.fromJson(body);
  }

  Future<DutyRoster> generateRoster(String weekStart) async {
    final body = await _post(
        '/api/v1/weeks/$weekStart/roster/generate', {'force': true},
        accepted: true);
    return DutyRoster.fromJson(body);
  }

  Future<DutyRoster> authorizeRoster(String weekStart) async {
    final body = await _post(
        '/api/v1/weeks/$weekStart/roster/authorize', {'approved': true});
    return DutyRoster.fromJson(body);
  }

  Future<List<AlertItem>> alerts(String weekStart) async {
    final body = await _get('/api/v1/weeks/$weekStart/alerts');
    final items = body['alerts'] as List<dynamic>? ?? [];
    return items
        .map((item) => AlertItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    bool authenticated = true,
    bool allowConflict = false,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers:
          authenticated ? _headers : const {'Content-Type': 'application/json'},
    );
    if (allowConflict && response.statusCode == 409) {
      return <String, dynamic>{};
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload, {
    bool accepted = false,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    final expected = accepted ? 202 : 200;
    final body = decodeJsonObjectFromBytes(response.bodyBytes);
    if (response.statusCode != expected && response.statusCode != 201) {
      throw ApiException(_errorMessage(body));
    }
    return body;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = decodeJsonObjectFromBytes(response.bodyBytes);
    if (response.statusCode >= 400) {
      throw ApiException(_errorMessage(body));
    }
    return body;
  }

  String _errorMessage(Map<String, dynamic> body) {
    final detail = body['detail'];
    if (detail is Map<String, dynamic>) {
      return detail['message'] as String? ?? 'הבקשה נכשלה';
    }
    return 'הבקשה נכשלה';
  }
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;

  bool get isManager => role == 'manager';

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
    );
  }
}

class ClientConfig {
  const ClientConfig({required this.timezone});

  final String timezone;

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    return ClientConfig(timezone: json['timezone'] as String);
  }
}

class ProgramatsiaStatus {
  const ProgramatsiaStatus({required this.status, this.fileName});

  final String status;
  final String? fileName;

  factory ProgramatsiaStatus.fromJson(Map<String, dynamic> json) {
    return ProgramatsiaStatus(
      status: json['status'] as String,
      fileName: json['file_name'] as String?,
    );
  }
}

class Shift {
  const Shift({
    required this.id,
    required this.label,
    required this.startsAt,
    required this.endsAt,
    this.location,
  });

  final String id;
  final String label;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? location;

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'] as String,
      label: json['label'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      location: json['location'] as String?,
    );
  }
}

class ShiftExclusion {
  const ShiftExclusion({required this.shiftId, required this.workerId});

  final String shiftId;
  final String workerId;

  factory ShiftExclusion.fromJson(Map<String, dynamic> json) {
    return ShiftExclusion(
      shiftId: json['shift_id'] as String,
      workerId: json['worker_id'] as String,
    );
  }
}

class ScheduleViewData {
  const ScheduleViewData({
    required this.programatsia,
    required this.shifts,
    required this.exclusions,
  });

  final ProgramatsiaStatus programatsia;
  final List<Shift> shifts;
  final List<ShiftExclusion> exclusions;
}

class DutyRoster {
  const DutyRoster({required this.status, required this.assignments});

  final String status;
  final List<RosterAssignment> assignments;

  factory DutyRoster.fromJson(Map<String, dynamic> json) {
    final items = json['assignments'] as List<dynamic>? ?? [];
    return DutyRoster(
      status: json['status'] as String,
      assignments: items
          .map(
              (item) => RosterAssignment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RosterAssignment {
  const RosterAssignment({required this.shiftId, required this.workerId});

  final String shiftId;
  final String workerId;

  factory RosterAssignment.fromJson(Map<String, dynamic> json) {
    return RosterAssignment(
      shiftId: json['shift_id'] as String,
      workerId: json['worker_id'] as String,
    );
  }
}

class AlertItem {
  const AlertItem(
      {required this.type, required this.severity, required this.status});

  final String type;
  final String severity;
  final String status;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      type: json['type'] as String,
      severity: json['severity'] as String,
      status: json['status'] as String,
    );
  }
}

String currentWeekStart() {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
  return '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

String formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month $hour:$minute';
}

String statusHebrew(String status) {
  return switch (status) {
    'missing' => 'חסר',
    'uploaded' => 'הועלה',
    'valid' => 'תקין',
    'invalid' => 'לא תקין',
    'converted' => 'הומר',
    'not_generated' => 'לא נוצר',
    'draft' => 'טיוטה',
    'ready_for_review' => 'מוכן לבדיקה',
    'authorized' => 'אושר',
    'open' => 'פתוח',
    'acknowledged' => 'טופל',
    'resolved' => 'נפתר',
    _ => status,
  };
}

Future<ScheduleViewData> loadScheduleViewData(
  ApiClient client,
  String weekStart,
) async {
  final initialResults = await Future.wait<Object>([
    client.programatsia(weekStart),
    client.exclusions(weekStart),
  ]);
  final programatsia = initialResults[0] as ProgramatsiaStatus;
  final exclusions = initialResults[1] as List<ShiftExclusion>;
  final shifts = shouldFetchSchedule(programatsia.status)
      ? await client.schedule(weekStart)
      : <Shift>[];

  return ScheduleViewData(
    programatsia: programatsia,
    shifts: shifts,
    exclusions: exclusions,
  );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 760;
                  final form = _LoginForm(
                    usernameController: usernameController,
                    passwordController: passwordController,
                    isLoading: auth.isLoading,
                    error: auth.error,
                    onSubmit: () async {
                      await ref.read(authProvider.notifier).login(
                            usernameController.text.trim(),
                            passwordController.text,
                          );
                      if (!mounted) {
                        return;
                      }
                      if (ref.read(authProvider).isAuthenticated) {
                        this.context.go('/schedule');
                      }
                    },
                  );
                  if (!wide) {
                    return form;
                  }
                  return Row(
                    children: [
                      Expanded(child: form),
                      const SizedBox(width: 28),
                      const Expanded(child: _LoginHero()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.usernameController,
    required this.passwordController,
    required this.isLoading,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isLoading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('שילוב',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('ניהול סידור שבועי',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 28),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  labelText: 'שם משתמש'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline), labelText: 'סיסמה'),
              obscureText: true,
              onSubmitted: (_) => onSubmit(),
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: isLoading ? null : onSubmit,
              icon: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('כניסה'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF165B5A),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _SchedulePatternPainter()),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(
                'משמרות, אילוצים ואישור במקום אחד',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    final block = Paint()
      ..color = const Color(0xFFC28738).withValues(alpha: 0.8);
    for (var x = 28.0; x < size.width; x += 72) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 28.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var index = 0; index < 9; index++) {
      final left = 34.0 + (index % 3) * 92;
      final top = 48.0 + index * 34;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, 132, 30), const Radius.circular(6)),
        block,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }
    final location = GoRouterState.of(context).uri.path;
    final selected = switch (location) {
      '/manager' => 1,
      '/roster' => 2,
      '/alerts' => 3,
      _ => 0,
    };
    final destinations = [
      const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'סידור'),
      if (auth.user!.isManager)
        const NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: 'ניהול'),
      const NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment),
          label: 'כוננות'),
      if (auth.user!.isManager)
        const NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'התראות'),
    ];
    final routes = [
      '/schedule',
      if (auth.user!.isManager) '/manager',
      '/roster',
      if (auth.user!.isManager) '/alerts',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('שילוב'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(auth.user!.displayName)),
          ),
          IconButton(
            tooltip: 'יציאה',
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 920) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex:
                      selected.clamp(0, destinations.length - 1).toInt(),
                  onDestinationSelected: (index) => context.go(routes[index]),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: child),
              NavigationBar(
                selectedIndex:
                    selected.clamp(0, destinations.length - 1).toInt(),
                onDestinationSelected: (index) => context.go(routes[index]),
                destinations: destinations,
              ),
            ],
          );
        },
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame(
      {required this.title, required this.children, super.key, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class SummaryTile extends StatelessWidget {
  const SummaryTile(
      {required this.icon,
      required this.title,
      required this.value,
      super.key});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final client = auth.client!;
    final weekStart = currentWeekStart();
    return FutureBuilder<ScheduleViewData>(
      future: loadScheduleViewData(client, weekStart),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final data = snapshot.data;
        final programatsia = data?.programatsia;
        final shifts = data?.shifts ?? [];
        final exclusions = data?.exclusions ?? [];
        return PageFrame(
          title: 'הסידור השבועי',
          children: [
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                    width: 260,
                    child: SummaryTile(
                        icon: Icons.today, title: 'שבוע', value: weekStart)),
                SizedBox(
                  width: 260,
                  child: SummaryTile(
                    icon: Icons.fact_check_outlined,
                    title: 'קובץ תכנון',
                    value: statusHebrew(programatsia?.status ?? 'missing'),
                  ),
                ),
                SizedBox(
                    width: 260,
                    child: SummaryTile(
                        icon: Icons.block_outlined,
                        title: 'אילוצים',
                        value: '${exclusions.length}')),
              ],
            ),
            const SizedBox(height: 18),
            if (loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (shifts.isEmpty)
              const EmptyState(
                  icon: Icons.event_busy, title: 'הסידור עדיין לא זמין')
            else
              for (final shift in shifts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ShiftCard(
                    shift: shift,
                    excluded: exclusions.any((item) =>
                        item.shiftId == shift.id &&
                        item.workerId == auth.user!.id),
                    onExclude: auth.user!.isManager
                        ? null
                        : () async {
                            await client.createExclusion(
                              weekStart: weekStart,
                              shiftId: shift.id,
                              workerId: auth.user!.id,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('האילוץ נשמר')));
                            }
                          },
                  ),
                ),
          ],
        );
      },
    );
  }
}

class ShiftCard extends StatelessWidget {
  const ShiftCard(
      {required this.shift, required this.excluded, this.onExclude, super.key});

  final Shift shift;
  final bool excluded;
  final FutureOr<void> Function()? onExclude;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 68,
              decoration: BoxDecoration(
                color: excluded
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shift.label,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      '${formatTime(shift.startsAt)} - ${formatTime(shift.endsAt)}'),
                  if (shift.location != null) Text(shift.location!),
                ],
              ),
            ),
            if (excluded)
              const Chip(label: Text('לא זמין'))
            else if (onExclude != null)
              OutlinedButton.icon(
                onPressed: () => onExclude!(),
                icon: const Icon(Icons.block),
                label: const Text('לא זמין'),
              ),
          ],
        ),
      ),
    );
  }
}

class ManagerScreen extends ConsumerStatefulWidget {
  const ManagerScreen({super.key});

  @override
  ConsumerState<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends ConsumerState<ManagerScreen> {
  bool uploading = false;
  String? selectedUploadFileName;
  String? uploadMessage;
  String? uploadError;

  Future<web.File?> pickProgramatsiaFile() {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept =
          '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    input.style.display = 'none';

    final body = web.document.body;
    if (body == null) {
      return Future.value(null);
    }

    final pickedFile = Completer<web.File?>();

    void complete(web.File? file) {
      if (!pickedFile.isCompleted) {
        pickedFile.complete(file);
      }
      input.remove();
    }

    input.addEventListener(
      'change',
      ((web.Event _) {
        complete(input.files?.item(0));
      }).toJS,
    );
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        complete(null);
      }).toJS,
    );
    body.appendChild(input);
    input.click();

    return pickedFile.future;
  }

  Future<void> uploadFile(ApiClient client, String weekStart) async {
    final file = await pickProgramatsiaFile();
    if (file == null) {
      return;
    }
    final fileName = file.name;
    if (!isXlsxFileName(fileName)) {
      setState(() {
        selectedUploadFileName = fileName;
        uploadMessage = null;
        uploadError = 'יש לבחור קובץ ‎.xlsx בלבד';
      });
      return;
    }
    setState(() {
      selectedUploadFileName = fileName;
      uploadMessage = null;
      uploadError = null;
    });
    final reader = web.FileReader();
    final loaded = Completer<Uint8List>();
    reader.addEventListener(
      'load',
      ((web.Event _) {
        final result = reader.result;
        if (result == null) {
          loaded.completeError(ApiException('לא ניתן לקרוא את הקובץ'));
          return;
        }
        loaded.complete((result as JSArrayBuffer).toDart.asUint8List());
      }).toJS,
    );
    reader.addEventListener(
      'error',
      ((web.Event _) {
        loaded.completeError(ApiException('לא ניתן לקרוא את הקובץ'));
      }).toJS,
    );
    reader.readAsArrayBuffer(file);
    final bytes = await loaded.future;
    if (bytes.isEmpty) {
      setState(() {
        uploadMessage = null;
        uploadError = 'הקובץ ריק';
      });
      return;
    }
    setState(() => uploading = true);
    try {
      await client.uploadProgramatsia(
          weekStart: weekStart, file: file, bytes: bytes);
      if (mounted) {
        setState(() {
          uploadMessage = 'הקובץ הועלה והסידור נוצר';
          uploadError = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('הקובץ הועלה')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          uploadMessage = null;
          uploadError = error.message;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(authProvider).client!;
    final weekStart = currentWeekStart();
    return FutureBuilder<ProgramatsiaStatus>(
      future: client.programatsia(weekStart),
      builder: (context, snapshot) {
        final status = snapshot.data;
        return PageFrame(
          title: 'ניהול שבועי',
          action: FilledButton.icon(
            onPressed: uploading ? null : () => uploadFile(client, weekStart),
            icon: uploading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('העלאת קובץ'),
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                    width: 280,
                    child: SummaryTile(
                        icon: Icons.calendar_view_week,
                        title: 'שבוע עבודה',
                        value: weekStart)),
                SizedBox(
                  width: 280,
                  child: SummaryTile(
                    icon: Icons.task_alt,
                    title: 'סטטוס תכנון',
                    value: statusHebrew(status?.status ?? 'missing'),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: SummaryTile(
                    icon: Icons.description_outlined,
                    title: 'קובץ אחרון',
                    value: status?.fileName ?? 'אין קובץ',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            UploadStatusPanel(
              selectedFileName: selectedUploadFileName ?? status?.fileName,
              message: uploadMessage,
              error: uploadError,
              uploading: uploading,
              onUpload: () => uploadFile(client, weekStart),
            ),
            const SizedBox(height: 18),
            const WorkflowBand(),
          ],
        );
      },
    );
  }
}

class UploadStatusPanel extends StatelessWidget {
  const UploadStatusPanel({
    required this.selectedFileName,
    required this.message,
    required this.error,
    required this.uploading,
    required this.onUpload,
    super.key,
  });

  final String? selectedFileName;
  final String? message;
  final String? error;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      colorScheme.secondary.withValues(alpha: 0.14),
                  foregroundColor: colorScheme.secondary,
                  child: const Icon(Icons.table_chart_outlined),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('קובץ פרוגרמטיקה',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('‎.xlsx בלבד',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (selectedFileName != null) ...[
              const SizedBox(height: 14),
              Text(
                selectedFileName!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, style: TextStyle(color: colorScheme.primary)),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: uploading ? null : onUpload,
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: const Text('בחירת קובץ והעלאה'),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkflowBand extends StatelessWidget {
  const WorkflowBand({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('העלאה', Icons.upload_file),
      ('בדיקה', Icons.rule),
      ('סידור', Icons.calendar_month),
      ('אילוצים', Icons.block),
      ('כוננות', Icons.assignment),
      ('אישור', Icons.verified),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final step in steps)
              SizedBox(
                width: 130,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(step.$2),
                    ),
                    const SizedBox(height: 8),
                    Text(step.$1,
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  Future<void> generate(ApiClient client, String weekStart) async {
    await client.generateRoster(weekStart);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> authorize(ApiClient client, String weekStart) async {
    await client.authorizeRoster(weekStart);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final client = auth.client!;
    final weekStart = currentWeekStart();
    return FutureBuilder<DutyRoster>(
      future: client.roster(weekStart),
      builder: (context, snapshot) {
        final roster = snapshot.data;
        return PageFrame(
          title: 'כוננות',
          action: auth.user!.isManager
              ? Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => generate(client, weekStart),
                      icon: const Icon(Icons.auto_mode),
                      label: const Text('יצירת טיוטה'),
                    ),
                    FilledButton.icon(
                      onPressed: roster?.status == 'ready_for_review'
                          ? () => authorize(client, weekStart)
                          : null,
                      icon: const Icon(Icons.verified),
                      label: const Text('אישור'),
                    ),
                  ],
                )
              : null,
          children: [
            SizedBox(
              width: 280,
              child: SummaryTile(
                icon: Icons.assignment_turned_in,
                title: 'סטטוס',
                value: statusHebrew(roster?.status ?? 'not_generated'),
              ),
            ),
            const SizedBox(height: 18),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (roster == null || roster.assignments.isEmpty)
              const EmptyState(
                  icon: Icons.assignment_late_outlined,
                  title: 'אין טיוטת כוננות')
            else
              for (final assignment in roster.assignments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_pin_circle_outlined),
                      title: Text(assignment.workerId),
                      subtitle: Text(assignment.shiftId),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(authProvider).client!;
    final weekStart = currentWeekStart();
    return FutureBuilder<List<AlertItem>>(
      future: client.alerts(weekStart),
      builder: (context, snapshot) {
        final alerts = snapshot.data ?? [];
        return PageFrame(
          title: 'התראות',
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (alerts.isEmpty)
              const EmptyState(
                  icon: Icons.notifications_none, title: 'אין התראות')
            else
              for (final alert in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        alert.severity == 'critical'
                            ? Icons.error_outline
                            : Icons.warning_amber,
                        color: alert.severity == 'critical'
                            ? Colors.red.shade700
                            : const Color(0xFFC28738),
                      ),
                      title: Text(_alertTitle(alert.type)),
                      subtitle: Text(statusHebrew(alert.status)),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  String _alertTitle(String type) {
    return switch (type) {
      'missing_programatsia' => 'קובץ תכנון חסר',
      'invalid_programatsia' => 'קובץ תכנון לא תקין',
      'roster_not_authorized' => 'כוננות לא אושרה',
      'roster_generation_failed' => 'יצירת הכוננות נכשלה',
      _ => type,
    };
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
