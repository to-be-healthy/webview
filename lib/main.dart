import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

import 'firebase_options.dart';

// 백그라운드 설정 코드는 맨 최상단에 위치해야함
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message ${message.messageId}');
}

final storage = FlutterSecureStorage(); // Secure Storage 인스턴스 생성

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  fcmSetting();

  if (!kIsWeb &&
      kDebugMode &&
      defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const MaterialApp(home: MyApp()));
  });
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

Future<void> fcmSetting() async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  print('User granted permission: ${settings.authorizationStatus}');

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
      playSound: true);

  var initialzationSettingsIOS = const DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  var initializationSettingsAndroid =
      const AndroidInitializationSettings('@mipmap/launcher_icon');

  var initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initialzationSettingsIOS);
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.getActiveNotifications();

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (message.notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification?.title,
          notification?.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              icon: '@mipmap/launcher_icon',
            ),
          ),
        );
      }
    },
  );

  // 토큰 리프레시 수신
  FirebaseMessaging.instance.onTokenRefresh.listen(
    (newToken) async {
      String? memberId = await storage.read(key: 'memberId');
      if (memberId != null) {
        await sendTokenToServer(int.parse(memberId), newToken);
      }
    },
  );
}

class _MyAppState extends State<MyApp> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // detect Android back button click
        final controller = webViewController;
        if (controller != null) {
          if (await controller.canGoBack()) {
            controller.goBack();
            return false;
          } else {
            // Show dialog when about to exit
            return await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('종료'),
                    content: Text('정말 건강해짐을 종료하시겠습니까?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text('아니요'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text('네'),
                      ),
                    ],
                  ),
                ) ??
                false;
          }
        }
        return true;
      },
      child: SafeArea(
        child: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: InAppWebView(
                  key: webViewKey,
                  initialUrlRequest: URLRequest(
                    url: WebUri("https://www.to-be-healthy.site/"),
                  ),
                  initialSettings: InAppWebViewSettings(
                    allowsBackForwardNavigationGestures: true,
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                  ),
                  onWebViewCreated: (controller) {
                    controller.addJavaScriptHandler(
                      handlerName: 'Channel',
                      callback: (args) async {
                        // 로그인 성공 시 FCM 토큰 발급 및 백엔드로 전송
                        int memberId = args[0];
                        await storage.write(
                            key: 'memberId', value: memberId.toString());
                        String? fcmToken =
                            await FirebaseMessaging.instance.getToken();
                        if (fcmToken != null) {
                          await sendTokenToServer(memberId, fcmToken);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> sendTokenToServer(int memberId, String fcmToken) async {
  debugPrint('memberId => $memberId');
  debugPrint('fcmToken => $fcmToken');
  String deviceType = Platform.isIOS ? 'IOS' : 'AOS'; // 플랫폼 타입 결정
  final response = await http.post(
    Uri.parse('https://api.to-be-healthy.site/push/v1/webview'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(
      {'memberId': memberId, 'token': fcmToken, 'deviceType': deviceType},
    ),
  );

  if (response.statusCode == 200) {
    debugPrint('Token saved successfully');
  } else {
    debugPrint('Failed to save token');
  }
}
