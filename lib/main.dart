import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
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
            ) ?? false;
          }
        }
        return true;
      },
      child: SafeArea(
        child: Scaffold(
            body: Column(children: <Widget>[
              Expanded(
                child: InAppWebView(
                  key: webViewKey,
                  initialUrlRequest: URLRequest(url: WebUri("http://10.0.2.2:3000/")),
                  initialSettings: InAppWebViewSettings(allowsBackForwardNavigationGestures: true),
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                ),
              ),
            ]
            )
        ),
      ),
    );
  }
}