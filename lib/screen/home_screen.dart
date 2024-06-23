import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HomeScreen extends StatelessWidget {
  // 생성자
  HomeScreen({Key? key}) : super(key: key);

  // 웹뷰 연동하기
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
          child: WebView(
            initialUrl: 'https://www.to-be-healthy.site',
            javascriptMode: JavascriptMode.unrestricted,
          ),
      )
    );
  }
}