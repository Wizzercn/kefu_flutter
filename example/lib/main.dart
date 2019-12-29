import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kefu_flutter/kefu_flutter.dart';

void main() async{
  SystemChrome.setSystemUIOverlayStyle(
  SystemUiOverlayStyle(statusBarColor: Color.fromRGBO(0, 0, 0, 0.0)));
  await SystemChrome.setPreferredOrientations(
  [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  return runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '在线客服',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        primaryColor: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter 在线客服 DEMO'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);
  final String title;
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  KeFuStore _keFu;

  void _action() {
    Navigator.push(context, CupertinoPageRoute(builder: (ctx){
      return _keFu.view();
    }));
  }

  @override
  void initState() {
    
    // 获得实例并监听数据动态
     _keFu = KeFuStore.getInstance;
     _keFu.addListener((){
      _keFu = KeFuStore.getInstance;
      debugPrint("_keFu对象变动");
      if(mounted) setState(() {});
    });

    super.initState();
    
  }


  @override
  Widget build(BuildContext context) {
    ThemeData themeData = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '当前用户id: ${_keFu.imUser?.id ?? 0}',
            ),
            Text(
              '当前有${_keFu.messageReadCount}条未读消息',
            ),
            Text(
              '欢迎使用在线客服',
            ),
            RaisedButton(
              color: themeData.primaryColor,
              child: Text("联系客服", style: TextStyle(color: Colors.white),), onPressed: () => _action()
            )
          ],
        ),
      ),
    );
  }
}
