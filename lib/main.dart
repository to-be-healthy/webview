import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

// 웹 페이지를 로드할 초기 URL
final String initialUrl = 'https://www.to-be-healthy.site/';

// 애플리케이션의 시작점
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 앱 실행할 준비가 완료될 때까지 기다린다.
  runApp(const MaterialApp(home: WebViewExample())); // 앱을 실행하고 WebViewExample 위젯을 홈으로 설정
}

// WebView를 사용하는 상태 관리 StatefulWidget 정의
class WebViewExample extends StatefulWidget {
  const WebViewExample({super.key});

  @override
  State<WebViewExample> createState() => _WebViewExampleState();
}

// WebViewExample의 상태를 관리하는 클래스
class _WebViewExampleState extends State<WebViewExample> with WidgetsBindingObserver {
  WebViewController? _controller; // WebView를 제어할 컨트롤러
  bool _isWebViewInitialized = false; // WebView 초기화 여부를 나타내는 플래그

  // State 객체가 최초 생성될 때 호출되는 메소드 (한번만 호출)
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 앱 생명주기 이벤트 감지 시작
    _initializeWebView(); // WebView 초기화 메소드 호출
  }

  // WebViewController를 초기화하고 설정
  void _initializeWebView() {
    // 플랫폼별 WebView 설정을 정의
    late final PlatformWebViewControllerCreationParams params;

    // 플랫폼이 WebKit (iOS) 인 경우
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{});
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    // WebViewController 인스턴스 생성
    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    // WebView 설정
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // JavaScript 사용 허용
      ..setNavigationDelegate(
        NavigationDelegate(
            onProgress: (int progress) { // 페이지 로드 진행 상황을 감지
              debugPrint('WebView is loading (progress : $progress%)');
            },
            onPageStarted: (String url) { // 페이지 로드 시작 시 호출
              debugPrint('Page started loading: $url');
            },
            onPageFinished: (String url) { // 페이지 로드 완료 시 호출
              debugPrint('Page finished loading: $url');
            },
            onWebResourceError: (WebResourceError error) { // 리소스 로드 에러 감지
              debugPrint('''
                        Page resource error:
                        code: ${error.errorCode}
                        description: ${error.description}
                        errorType: ${error.errorType}
                        isForMainFrame: ${error.isForMainFrame}
            ''');
            },
            onHttpError: (HttpResponseError error) { // HTTP 에러 감지
              debugPrint('Error occurred on page: ${error.response?.statusCode}');
            },
            onUrlChange: (UrlChange change) { // URL 변경 감지
              debugPrint('url change to ${change.url}');
            }
        ),
      )
      ..setUserAgent('random')
      ..loadRequest(Uri.parse(initialUrl)); // 초기 URL 로드

    // 안드로이드 플랫폼 설정
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true); // 디버깅 모드 활성화
      (controller.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false); // 사용자 제스처 없이 미디어 재생 허용
    }

    // 상태 업데이트
    setState(() {
      _controller = controller;
      _isWebViewInitialized = true;
    });
  }

  // 위젯이 파괴될 때 호출되는 메소드
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 앱 생명주기 이벤트 감지 중단
    super.dispose();
  }

  // 앱 생명주기 상태 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { // 앱이 다시 활성화되면 초기 URL 재로드
      _controller?.loadRequest(Uri.parse(initialUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { // 뒤로 가기 버튼 눌렀을 때 처리
        if (_isWebViewInitialized && await _controller!.canGoBack()) { // WebView에서 뒤로 갈 수 있으면
          _controller!.goBack(); // WebView 뒤로 가기
          return false; // 앱 종료 막기
        } else {
          final shouldExit = await _showExitConfirmationDialog(context); // 종료 확인 다이얼로그 표시
          return shouldExit;
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: GestureDetector(
            onHorizontalDragEnd: (DragEndDetails details) { // 수평 드래그 감지
              _handleHorizontalDrag(details);
            },
            child: RefreshIndicator(
              onRefresh: () => _isWebViewInitialized ? _controller!.reload() : Future.value(), // 새로고침
              child: _isWebViewInitialized
                  ? WebViewWidget(controller: _controller!) // WebView 표시
                  : Center(child: CircularProgressIndicator()), // 로딩 중 표시
            ),
          ),
        ),
      ),
    );
  }

  // 수평 드래그 처리
  void _handleHorizontalDrag(DragEndDetails details) async {
    if (_isWebViewInitialized) {
      if (details.primaryVelocity != null && details.primaryVelocity! > 0) { // 오른쪽으로 드래그
        if (await _controller!.canGoBack()) {
          _controller!.goBack(); // WebView 뒤로 가기
        }
      } else if (details.primaryVelocity != null && details.primaryVelocity! < 0) { // 왼쪽으로 드래그
        if (await _controller!.canGoForward()) {
          _controller!.goForward(); // WebView 앞으로 가기
        }
      }
    }
  }

  // HTTP 인증 요청 다이얼로그 표시
  Future<void> openDialog(HttpAuthRequest httpRequest) async {
    final TextEditingController usernameTextController = TextEditingController();
    final TextEditingController passwordTextController = TextEditingController();

    return showDialog(
      context: context,
      barrierDismissible: false, // 다이얼로그 외부 터치로 닫히지 않도록 설정
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${httpRequest.host}: ${httpRequest.realm ?? '-'}'), // 다이얼로그 제목
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  decoration: const InputDecoration(labelText: 'Username'), // 사용자명 입력 필드
                  autofocus: true,
                  controller: usernameTextController,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Password'), // 비밀번호 입력 필드
                  controller: passwordTextController,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                httpRequest.onCancel(); // 인증 요청 취소
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                httpRequest.onProceed(
                  WebViewCredential(
                    user: usernameTextController.text,
                    password: passwordTextController.text,
                  ),
                ); // 인증 요청 진행
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: const Text('Authenticate'),
            ),
          ],
        );
      },
    );
  }

  // 종료 확인 다이얼로그 표시
  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    return await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exit App'),
          content: const Text('Do you really want to exit the app?'), // 종료 확인 메시지
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // 종료 취소
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // 앱 종료
              },
              child: const Text('Exit'),
            ),
          ],
        );
      },
    ) ??
        false;
  }
}

// WebView의 탐색 컨트롤 위젯
class NavigationControls extends StatelessWidget {
  const NavigationControls({super.key, required this.webViewController});

  final WebViewController webViewController;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.arrow_back_ios), // 뒤로 가기 아이콘
          onPressed: () async {
            if (await webViewController.canGoBack()) {
              await webViewController.goBack(); // WebView 뒤로 가기
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No back history item')), // 뒤로 갈 페이지 없음 메시지
                );
              }
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward_ios), // 앞으로 가기 아이콘
          onPressed: () async {
            if (await webViewController.canGoForward()) {
              await webViewController.goForward(); // WebView 앞으로 가기
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No forward history item')), // 앞으로 갈 페이지 없음 메시지
                );
              }
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.replay), // 새로고침 아이콘
          onPressed: () => webViewController.reload(), // WebView 새로고침
        ),
      ],
    );
  }
}
