import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'navigation_screen.dart';
import 'otp_screen.dart';

// Service & Screen Imports
import 'sos_model.dart';
import 'camera_service.dart';
import 'host_screen.dart';
import 'viewer_screen.dart';
import 'record_service.dart';
import 'video_record_service.dart';
import 'location_sms_service.dart';
import 'ai_screen.dart';
import 'VaultScreen.dart';
import 'app_theme.dart';
import 'package:email_otp/email_otp.dart';

class RemoteManager {
  static final RemoteManager _instance = RemoteManager._internal();
  factory RemoteManager() => _instance;
  RemoteManager._internal();
  IO.Socket? socket;
  String? myHostCode;
  String? savedGroupLink;

  Future<void> init() async {
    socket = IO.io('https://safely-871c.onrender.com', IO.OptionBuilder().setTransports(['websocket']).enableAutoConnect().build());
    SharedPreferences prefs = await SharedPreferences.getInstance();
    myHostCode = prefs.getString('h_code') ?? (1000 + Random().nextInt(9000)).toString();
    savedGroupLink = prefs.getString('wa_group_link') ?? "";
    await prefs.setString('h_code', myHostCode!);
  }

  Future<void> saveGroupLink(String link) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    savedGroupLink = link;
    await prefs.setString('wa_group_link', link);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'guard_final',
        channelName: 'GuardianX',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 5000, allowWakeLock: true),
    );
  }
  await RemoteManager().init();
  runApp(const GuardianXApp());
}

class GuardianXApp extends StatelessWidget {
  const GuardianXApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: const SplashScreen(),
  );
}

// --- 1. SPLASH SCREEN ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _zoomController;
  late Animation<double> _zoomAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _zoomController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..forward();

    _zoomAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.linear),
    );

    _fadeController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _fadeController.forward();

    Timer(const Duration(seconds: 6), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const String eliteImageUrl = "https://chatgpt.com/backend-api/estuary/content?id=file_000000001df07208b91858653e847675&ts=494381&p=fs&cid=1&sig=6728f8a7c1a06dccc5ff9559d0b9726ecd35086db0d736ff7eba2c9e8c043060&v=0";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScaleTransition(
            scale: _zoomAnimation,
            child: Image.network(
              eliteImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.95),
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            right: -50,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.15),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  "GUARDIAN X",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 18,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.cyanAccent.withOpacity(0.7), blurRadius: 25),
                      const Shadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "ENCRYPTED SAFETY PROTOCOL v3.0",
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 6,
                    color: Colors.cyanAccent.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 100),
                Container(
                  width: 180,
                  height: 1,
                  child: const LinearProgressIndicator(
                    backgroundColor: Colors.white10,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "ESTABLISHING SECURE CLOUD LINK",
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 7,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- 2. LOGIN PAGE ---
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isSending = false;
  EmailOTP myAuth = EmailOTP();

  final emailController = TextEditingController();
  final passController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  void _sendOTP() async {
    if (emailController.text.isEmpty || !emailController.text.contains("@")) {
      _showSnack("Please enter a valid email");
      return;
    }

    setState(() => isSending = true);

    try {
      myAuth.setConfig(
        appEmail: "guard@safety.com",
        appName: "GuardianX Hub",
        userEmail: emailController.text,
        otpLength: 4,
        otpType: OTPType.digitsOnly,
      );

      bool result = await myAuth.sendOTP();

      if (result) {
        _showSnack("OTP Sent! Check your email.");
      } else {
        _showSnack("Mail Server Busy. Using Demo Code: 1234", isError: true);
      }

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (c) => OTPScreen(
          auth: myAuth,
          email: emailController.text,
          phone: phoneController.text,
          isDemoMode: !result,
        )));
      }
    } catch (e) {
      _showSnack("Network Error. Using Demo Code: 1234", isError: true);

      Navigator.push(context, MaterialPageRoute(builder: (c) => OTPScreen(
        auth: myAuth,
        email: emailController.text,
        phone: phoneController.text,
        isDemoMode: true,
      )));
    } finally {
      setState(() => isSending = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.orange : Colors.blue,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.shield, size: 80, color: AppTheme.crimson),
            const SizedBox(height: 20),
            const Text("GUARDIAN X", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: AppTheme.textPrimary)),
            const SizedBox(height: 50),

            if (!isLogin) ...[
              _field(nameController, "Full Name", Icons.person_outline),
              const SizedBox(height: 15),
              _field(phoneController, "Phone", Icons.phone_android),
              const SizedBox(height: 15),
            ],

            _field(emailController, "Guardian Email", Icons.email_outlined),
            const SizedBox(height: 15),

            if (isLogin)
              _field(passController, "Security Passkey", Icons.vpn_key_outlined, isPass: true),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                onPressed: isSending ? null : (isLogin ? () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const MainNavigation()));
                } : _sendOTP),
                child: isSending
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(isLogin ? "AUTHORIZE" : "GENERATE OTP"),
              ),
            ),

            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? "Create Account" : "Back to Login", style: const TextStyle(color: AppTheme.azure)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textMuted),
        prefixIcon: Icon(icon, color: AppTheme.crimson),
        filled: true,
        fillColor: AppTheme.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppTheme.cardBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppTheme.cardBorder)),
      ),
    );
  }
}

// --- 3. MAIN NAVIGATION ---
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override State<MainNavigation> createState() => _MainNavigationState();
}
class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  List<EmergencyContact> myContacts = [EmergencyContact(id: "1", name: "Emergency Contact", number: "911")];
  late List<SOSLevel> myLevels = [
    SOSLevel(name: "Lvl 1", color: Colors.amber, customMessage: "Checking in.", activationGesture: "Single Tap"),
    SOSLevel(name: "Lvl 2", color: Colors.orange, customMessage: "Unsafe.", activationGesture: "Double Tap"),
    SOSLevel(name: "Lvl 3", color: Colors.red, recordVideo: true, recordAudio: true, liveStream: true, customMessage: "EMERGENCY!", activationGesture: "Long Press"),
  ];

  @override void initState() {
    super.initState();
    if (!kIsWeb) [Permission.camera, Permission.microphone, Permission.storage, Permission.location, Permission.sms].request();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(levels: myLevels, contacts: myContacts),
      const NavigationScreen(),
      GuardianScreen(contacts: myContacts, onUpdate: (l) => setState(() => myContacts = l)),
      ConfigScreen(levels: myLevels, onUpdate: (l) => setState(() => myLevels = l)),
      const AIScreen(),
      const VaultScreen(),
      ViewerEntryTab(socket: RemoteManager().socket!)
    ];
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppTheme.crimson,
        unselectedItemColor: AppTheme.textMuted,
        backgroundColor: AppTheme.surface,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shield), label: "SOS"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "People"),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Config"),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: "AI"),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: "Vault"),
          BottomNavigationBarItem(icon: Icon(Icons.visibility), label: "Watch"),
        ],
      ),
    );
  }
}

// --- 4. HOME (CENTERED SOS) ---
class HomeScreen extends StatefulWidget {
  final List<SOSLevel> levels; final List<EmergencyContact> contacts;
  const HomeScreen({super.key, required this.levels, required this.contacts});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int taps = 0; bool armed = false; bool isRunning = false;

  void trigger(SOSLevel lvl) async {
    if (!armed) return;
    setState(() => isRunning = true);
    if (!kIsWeb) await FlutterForegroundTask.startService(notificationTitle: "GuardianX ARMED", notificationText: "Protection Active");

    await LocationSmsService().triggerAlerts(
      contacts: widget.contacts,
      roomCode: RemoteManager().myHostCode!,
      customMsg: lvl.customMessage,
      useSMS: lvl.sendSMS,
      useWA: lvl.sendWhatsApp,
      groupLink: RemoteManager().savedGroupLink,
    );

    if (lvl.recordAudio) await RecordService().startLocalRecord();
    await CameraService().startStreaming(RemoteManager().socket!, RemoteManager().myHostCode!);
    if (lvl.recordVideo && CameraService().localStream != null) await VideoRecordService().startVideoRecording(CameraService().localStream!);
    if (lvl.liveStream) Navigator.push(context, MaterialPageRoute(builder: (c) => HostScreen(roomCode: RemoteManager().myHostCode!)));
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Tactical Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: (armed ? AppTheme.emerald : AppTheme.crimson).withOpacity(0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: (armed ? AppTheme.emerald : AppTheme.crimson).withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: armed ? AppTheme.emerald : AppTheme.crimson,
                    boxShadow: [
                      BoxShadow(
                        color: armed ? AppTheme.emerald : AppTheme.crimson,
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  armed
                      ? "SYSTEM ARMED • ROOM ${RemoteManager().myHostCode}"
                      : "DEFENSE SYSTEM LOCKED",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: armed ? AppTheme.emerald : AppTheme.crimson,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          if (!armed) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                    (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: taps > index ? AppTheme.crimson : AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Tap button 3 times to ARM defense trigger",
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],

          const SizedBox(height: 40),

          // Central Tactical SOS Trigger
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!armed) {
                setState(() {
                  taps++;
                  if (taps >= 3) armed = true;
                });
              } else {
                _showPicker();
              }
            },
            child: Container(
              height: 260,
              width: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: armed
                      ? [const Color(0xFF064E3B), const Color(0xFF022C22), AppTheme.background]
                      : [const Color(0xFF4C0519), const Color(0xFF27050E), AppTheme.background],
                  stops: const [0.3, 0.7, 1.0],
                ),
                border: Border.all(
                  color: armed ? AppTheme.emerald : AppTheme.crimson,
                  width: 3.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (armed ? AppTheme.emerald : AppTheme.crimson).withOpacity(0.25),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.power_settings_new_rounded,
                      size: 78,
                      color: armed ? AppTheme.emerald : AppTheme.crimson,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      armed ? "TRIGGER SOS" : "LOCKED",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 2.5,
                        color: armed ? AppTheme.emerald : AppTheme.crimson,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      armed ? "Tap to choose tier" : "3-tap security lock",
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),

          if (isRunning)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.crimson,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () {
                RecordService().stopLocalRecord();
                VideoRecordService().stopVideoRecording();
                CameraService().stopEverything();
                LocationSmsService().stop();
                FlutterForegroundTask.stopService();
                setState(() => isRunning = false);
              },
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
              label: const Text(
                "STOP ALL PROCESSES",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
        ],
      ),
    ),
  );

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.levels.map((l) => ListTile(
          leading: Icon(Icons.warning, color: l.color),
          title: Text(l.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          onTap: () {
            Navigator.pop(ctx);
            trigger(l);
          },
        )).toList(),
      ),
    );
  }
}

// --- 5. CONFIG ---
class ConfigScreen extends StatefulWidget {
  final List<SOSLevel> levels; final Function onUpdate;
  const ConfigScreen({super.key, required this.levels, required this.onUpdate});
  @override State<ConfigScreen> createState() => _ConfigState();
}
class _ConfigState extends State<ConfigScreen> with SingleTickerProviderStateMixin {
  late TabController _t;
  @override void initState() { super.initState(); _t = TabController(length: 3, vsync: this); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("SOS Configuration"),
        bottom: TabBar(
          controller: _t,
          indicatorColor: AppTheme.crimson,
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [Tab(text: "Level 1"), Tab(text: "Level 2"), Tab(text: "Level 3")],
        ),
      ),
      body: TabBarView(
        controller: _t,
        children: widget.levels.map((l) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text("Send SMS Alert", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.sendSMS,
                    activeColor: AppTheme.crimson,
                    onChanged: (v) => setState(() => l.sendSMS = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Background Auto-SMS", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: const Text("Sends silently without user confirmation", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    value: l.autoSms,
                    activeColor: AppTheme.emerald,
                    onChanged: (v) => setState(() => l.autoSms = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Send WhatsApp Broadcast", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.sendWhatsApp,
                    activeColor: AppTheme.emerald,
                    onChanged: (v) => setState(() => l.sendWhatsApp = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Physical Audio Record", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.recordAudio,
                    activeColor: AppTheme.amber,
                    onChanged: (v) => setState(() => l.recordAudio = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Physical Video Record", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.recordVideo,
                    activeColor: AppTheme.azure,
                    onChanged: (v) => setState(() => l.recordVideo = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Notify Police", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.notifyPolice,
                    activeColor: AppTheme.crimson,
                    onChanged: (v) => setState(() => l.notifyPolice = v),
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  SwitchListTile(
                    title: const Text("Notify Hospital", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    value: l.notifyHospital,
                    activeColor: AppTheme.crimson,
                    onChanged: (v) => setState(() => l.notifyHospital = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text("Emergency Alert Message:", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              maxLines: 2,
              controller: TextEditingController(text: l.customMessage),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cardBorder)),
              ),
              onChanged: (v) => l.customMessage = v,
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ListTile(
                title: const Text("Activation Gesture", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                trailing: DropdownButton<String>(
                  dropdownColor: AppTheme.card,
                  value: l.activationGesture,
                  style: const TextStyle(color: AppTheme.azure, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: ["Single Tap", "Double Tap", "Long Press"]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => l.activationGesture = v!);
                    widget.onUpdate(widget.levels);
                  },
                ),
              ),
            ),
          ],
        )).toList(),
      ),
    );
  }
}

// --- 6. PEOPLE TAB (GROUP SETUP BRIDGE) ---
class GuardianScreen extends StatefulWidget {
  final List<EmergencyContact> contacts; final Function onUpdate;
  const GuardianScreen({super.key, required this.contacts, required this.onUpdate});
  @override State<GuardianScreen> createState() => _GuardianScreenState();
}
class _GuardianScreenState extends State<GuardianScreen> {
  final _linkCtrl = TextEditingController(text: RemoteManager().savedGroupLink);
  void _generateGroup() async {
    String allNumbers = widget.contacts.map((e) => e.number).join(", ");
    await Clipboard.setData(ClipboardData(text: allNumbers));
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Ready to Create Group"),
      content: const Text("Numbers copied to clipboard. Open WhatsApp, create a group, and paste the link below."),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
          onPressed: () => launchUrl(Uri.parse("https://wa.me/")),
          child: const Text("OPEN WHATSAPP"),
        )
      ],
    ));
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Guardian Hub"),
        actions: [IconButton(icon: const Icon(Icons.person_add, color: AppTheme.azure), onPressed: () => _add(context))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.groups, color: AppTheme.emerald, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("WhatsApp Emergency Group", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 15)),
                          Text("One unified broadcast window for all contacts", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
                    onPressed: _generateGroup,
                    child: const Text("1. COPY NUMBERS & OPEN WHATSAPP"),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _linkCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "2. Paste Group Invite Link",
                    labelStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.cardBorder)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.azure,
                      side: const BorderSide(color: AppTheme.azure),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      RemoteManager().saveGroupLink(_linkCtrl.text);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("WhatsApp group link saved!")));
                    },
                    child: const Text("3. SAVE BROADCAST LINK"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text("EMERGENCY CONTACTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ...widget.contacts.map((c) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.azure.withOpacity(0.15),
                child: const Icon(Icons.person, color: AppTheme.azure),
              ),
              title: Text(c.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(c.number, style: const TextStyle(color: AppTheme.textSecondary)),
            ),
          )),
        ],
      ),
    );
  }
  void _add(BuildContext context) {
    final n = TextEditingController(), p = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Add"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: "Name")),
            TextField(controller: p, decoration: const InputDecoration(labelText: "Phone")),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              widget.contacts.add(EmergencyContact(id: "1", name: n.text, number: p.text));
              widget.onUpdate(widget.contacts);
              Navigator.pop(c);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

// --- 7. VIEWER TAB ---
class ViewerEntryTab extends StatelessWidget {
  final IO.Socket socket;
  const ViewerEntryTab({super.key, required this.socket});

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.crimson.withOpacity(0.12),
                border: Border.all(color: AppTheme.crimson.withOpacity(0.3), width: 2),
              ),
              child: const Icon(Icons.live_tv_rounded, size: 64, color: AppTheme.crimson),
            ),
            const SizedBox(height: 24),
            const Text(
              "Tactical Remote Watch",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter the 6-digit Host Room Code to stream encrypted video & remote-control victim sensors.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: TextField(
                controller: c,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: const InputDecoration(
                  hintText: "ENTER ROOM CODE",
                  hintStyle: TextStyle(fontSize: 13, letterSpacing: 1.5, color: AppTheme.textMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.crimson,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  if (c.text.trim().isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (x) => ViewerScreen(socket: socket, roomCode: c.text.trim()),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.visibility),
                label: const Text("CONNECT TO STREAM", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}