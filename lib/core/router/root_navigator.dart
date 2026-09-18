import 'package:flutter/widgets.dart';

/// 앱 전체의 맨 아래 Navigator.
/// 화면 트리 바깥(MaterialApp.builder)에서 팝업을 띄울 때 이 키의 context 를 쓴다.
/// builder 의 context 는 Navigator 보다 위에 있어서 showDialog 가 실패한다.
final rootNavigatorKey = GlobalKey<NavigatorState>();
