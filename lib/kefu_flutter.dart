import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mimc/flutter_mimc.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import 'models/customer_service.dart';
import 'models/im_message.dart';
import 'models/im_token_info.dart';
import 'models/im_user.dart';
import 'models/robot.dart';
import 'models/upload_secret.dart';
import 'utils/im_utils.dart';
import 'widgets/cached_network_image.dart';
import 'widgets/emoji_panel.dart';
import 'widgets/knowledge_message.dart';
import 'widgets/photo_message.dart';
import 'widgets/system_message.dart';
import 'widgets/text_message.dart';

/// MiNiIm screen
class KeFu extends StatefulWidget{
  @override
  _KeFuState createState() => _KeFuState();
}

/// im screen state
class _KeFuState extends State<KeFu>{

  /// API 接口
  String _host = "http://kf.aissz.com:666/v1";                   /// IM 后台网关
  static const String _IM_REGISTER =   "/public/register";       /// IM 注册初始化IM账号
  static const String _IM_ACTIVITY =   "/public/activity";       /// IM 上报最后活动时间 /uid
  static const String _IM_GET_ROBOT =  "/public/robot/1";        /// IM 获取机器人      /platform
  static const String _IM_GET_READ =   "/public/read";           /// IM 获取未读消息    /uid
  static const String _IM_CLEAN_READ = "/public/clean_read";     /// IM 清除未读消息    /uid
  static const String _IM_UPLOAD_SECRET = "/public/secret";      /// IM 获取上传配置

  /// 小米消息云配置
  static const String _APP_ID = "2882303761518282099";
  static const String _APP_KEY = "5521828290099";
  static const String _APP_SECRET = "516JCA60FdP9bHQUdpXK+Q==";

  FocusNode _focusNode = FocusNode();
  TextEditingController _editingController = TextEditingController();
  ScrollController _scrollController = ScrollController();
  Dio _http;                      /// http
  SharedPreferences _prefs;       /// 缓存对象
  ImUser _imUser;                 /// IM 用户对象
  Robot _robot;                   /// 机器人对象
  ImTokenInfo _imTokenInfo;       /// IM 签名对象
  FlutterMimc _flutterMimc;       /// IM 插件对象
  bool _isShowEmoJiPanel = false; /// 是否显示表情面板
  bool _isFirstConnect = true;    /// 是否是首次连线
  bool _isCustomerService  = false;    /// 当前是否是客服连线
  CustomerService _serviceUser;        /// 客服信息
  List<ImMessage> _messagesRecord = [];/// 聊天记录
  bool _isScrollEnd = false;  /// 没有更多记录了
  bool _isMorLoading = false; /// 加载更多...
  bool _isPong = false;       /// 显示对方输入中...
  bool _isShowFileButtons = false; /// 是否显示文件按钮面板
  UploadSecret _uploadSecret;      /// 上传配置对象

  /// 消息接收方账号 机器人 或 客服
  int get _toAccount => _isCustomerService && _serviceUser != null ? _serviceUser.id : _robot.id;

  /// init
  void _init() async{
    await _prefsInstance();
    await _dioInstance();
    await _getUploadSecret();
    await _registerImAccount();
    await _getRobot();
    if(_imTokenInfo != null){
      await _flutterMimcInstance();
      _upImLastActivity();
    }else{
      debugPrint("init fail");
    }
    // 监听滚动条
    _scrollController?.addListener(() => _onScrollViewControllerAddListener());
  }

  // 监听滚动条
  void _onScrollViewControllerAddListener() async{
    try {
      ScrollPosition position = _scrollController.position;
      // 判断是否到底部
      if (position.pixels + 10.0 > position.maxScrollExtent && !_isScrollEnd && !_isMorLoading) {
        _isMorLoading = true;
        await Future.delayed(Duration(milliseconds: 1000));
        List<ImMessage> _localMessages = await _getLocalMessageRecord();
        if(_localMessages.length <= 0)  _isScrollEnd = true;
        _messagesRecord.insertAll(0, _localMessages);
        _isMorLoading = false;
        setState(() {});
      }

    }catch(e){
      debugPrint(e);
    }
  }

  /// 实例化 FlutterMimc
  Future<void> _flutterMimcInstance() async{
    _flutterMimc = FlutterMimc.init(
        debug: false,
        appId: _APP_ID,
        appKey: _APP_KEY,
        appSecret: _APP_SECRET,
        appAccount: _imUser.id.toString()
    );
    if(_flutterMimc != null){
      _flutterMimc.login();
      _addMimcEvent();
    }
  }

  /// mimc事件监听
  StreamSubscription _subStatus;
  StreamSubscription _subHandleMessage;
  void _addMimcEvent(){

    /// 状态发生改变
    _subStatus = _flutterMimc.addEventListenerStatusChanged().listen((bool status) async{
      print("IM状态变更=======$status");
      if(_prefs.getBool("_isCustomerService") == true){
        _isCustomerService = true;
        int _customerServiceId = _prefs.getInt("_customerServiceId");
        if(_customerServiceId != null && _customerServiceId != -1){
          String _serviceUseStr = _prefs.getString("service_user_$_customerServiceId");
          if(_serviceUseStr != null){
            _serviceUser= CustomerService.fromJson(json.decode(_serviceUseStr));
          }else{
            _isCustomerService = false;
          }
        }
      }
      if(_isFirstConnect && status && !_isCustomerService){
        _isFirstConnect = false;
        // 发送握手消息
        MessageHandle messageHandle =  _createMessage(toAccount: _toAccount, msgType: "handshake", content: "我要对机器人问好");
        _sendMessage(messageHandle);
      }
      setState(() {});
    });

    /// 消息监听
    _subHandleMessage = _flutterMimc.addEventListenerHandleMessage().listen((MIMCMessage msg) async{
      ImMessage message = ImMessage.fromJson(json.decode(utf8.decode(base64Decode(msg.payload))));
      debugPrint("收到消息======${message.toJson()}");
      switch(message.bizType){
        case "transfer":
          _serviceUser= CustomerService.fromJson(json.decode(message.payload));
          _prefs.setString("service_user_" + _serviceUser.id.toString(), message.payload);
          _prefs.setInt("_customerServiceId", _serviceUser.id);
          _prefs.setBool("_isCustomerService", true);
          _isCustomerService = true;
          MessageHandle msgHandle =  _createMessage(toAccount: _toAccount, msgType: "handshake", content: "与客服握握手鸭");
          _sendMessage(msgHandle);
          break;
        case "end":
        case "timeout":
          _serviceUser = null;
          _isCustomerService = false;
          _prefs.setBool("_isCustomerService", false);
          _prefs.setInt("_customerServiceId", -1);
          break;
        case "pong":
          if(_isPong) return;
          _isPong = true;
          setState(() {});
          await Future.delayed(Duration(milliseconds: 1500));
          _isPong = false;
          break;
        case "cancel":
          message.key = int.parse(message.payload);
          _deleteMessage(message);
          break;
      }
      _cachePushMessage(message);
      if(message.bizType != "pong") _toScrollEnd();
      setState(() {});
    });

  }

  /// 实例化 dio
  Future<void> _dioInstance() async{
    _http = Dio();
    _http.options.baseUrl = _host;
    _http.options.connectTimeout = 60000;
    _http.options.receiveTimeout = 60000;
    _http.options.headers = {};
  }

  /// 实例化 SharedPreferences
  Future<void> _prefsInstance() async{
    _prefs = await SharedPreferences.getInstance();
  }

  /// 注册IM账号
  Future<void> _registerImAccount() async{
    try {
      int imAccount = _prefs.getInt("ImAccount") ?? 0;
      Response response = await _http.post(_IM_REGISTER, data: {
        "type": 0,
        "uid": 0,
        "platform": Platform.isIOS ? 2 : 6,
        "account_id": imAccount
      });
      if (response.data["code"] == 200) {
        _imTokenInfo = ImTokenInfo.fromJson(response.data["data"]["token"]["data"]);
        _imUser = ImUser.fromJson(response.data["data"]["user"]);
        _prefs.setInt("ImAccount", _imUser.id);
        // 获取缓存记录
        _messagesRecord = await _getLocalMessageRecord();
        setState(() {});
      } else {
        // 1秒重试
        debugPrint(response.data["error"]);
        await Future.delayed(Duration(milliseconds: 1000));
        _registerImAccount();
      }
    }catch(e){
      debugPrint(e);
    }
  }

  /// 获取机器人信息
  Future<void> _getRobot() async{
    try {
      Response response = await _http.get(_IM_GET_ROBOT);
      if (response.data["code"] == 200) {
        _robot = Robot.fromJson(response.data["data"]);
        _prefs.setString("robot_" + _robot.id.toString(), json.encode(response.data["data"]));
      } else {
        // 1秒重试
        debugPrint(response.data["error"]);
        await Future.delayed(Duration(milliseconds: 1000));
        _getRobot();
      }
    }catch(e){
      debugPrint(e);
    }
  }

  /// 上报IM最后活动时间
  Future<void> _upImLastActivity() async{
    Timer.periodic(Duration(milliseconds: 20000), (_){
      _http.get(_host + _IM_ACTIVITY + '/' + _imUser.id.toString());
    });
  }

  /// 获取上传文件配置
  Future<void> _getUploadSecret() async{
    Response response = await _http.get(_host + _IM_UPLOAD_SECRET);
    if(response.data["code"] == 200){
      _uploadSecret = UploadSecret.fromJson(response.data["data"]);
    }else{
      await Future.delayed(Duration(milliseconds: 1000));
      _getUploadSecret();
    }
  }

  /// 获取IM 未读消息
  Future<int> _getReadCount() async{
    int _count = 0;
    Response response = await _http.get(_host + _IM_GET_READ + '/' + _imUser.id.toString());
    if(response.data["code"] == 200){
      _count = response.data["data"];
    }
    return _count;
  }

  /// 清除IM未读消息
  Future<void> _cleanRead() async{
    await _http.get(_host + _IM_CLEAN_READ + '/' + _imUser.id.toString());
  }

  // 处理消息缓存并加入到list message
  void _cachePushMessage(ImMessage msg, {bool isCache = true, bool isMemoryCache = true}) async{
    if(isMemoryCache){
      ImMessage newMsg = await _handlerMessage(msg);
      _messagesRecord.add(newMsg);
    }
    if(isCache) {
      String bizType = msg.bizType;
      if(bizType == "welcome" || bizType == "pong") return;
      List<String> cacheMessages = _prefs.getStringList("miniImAppMessageRecord_${_imUser.id}")  ?? [];
      cacheMessages.add(json.encode(msg.toJson()));
      _prefs.setStringList("miniImAppMessageRecord_${_imUser.id}", cacheMessages);
    }
    setState(() {});
  }

  // 获取本地缓存消息
  Future<List<ImMessage>> _getLocalMessageRecord() async{
    const pageSize = 15;
    List<ImMessage> _localMessages = [];
    List<String> _localMessagesStr = _prefs.getStringList("miniImAppMessageRecord_${_imUser.id}");
    if(_localMessagesStr != null){
      List<ImMessage> _localMessageAll = _localMessagesStr.map((i) => ImMessage.fromJson(json.decode(i))).toList();
      if(_messagesRecord.length == 0){
        _localMessages = _localMessageAll.sublist(_localMessageAll.length <= pageSize ? 0 :  _localMessageAll.length - pageSize, _localMessageAll.length);
      }else{
        var lastIndex;
        for(int i = _localMessageAll.length - 1; i >= 0; i--){
          if(_localMessageAll[i].timestamp == _messagesRecord[0].timestamp){
            lastIndex = i;
            break;
          }
        }
        if(lastIndex == null || lastIndex == 1){
          return [];
        }
        if(lastIndex <= pageSize){
          _localMessages = _localMessageAll.sublist(0, lastIndex);
        }else{
          _localMessages = _localMessageAll.sublist(lastIndex - pageSize, lastIndex);
        }
      }
    }
    for(int b = 0; b<_localMessages.length; b++){
      ImMessage msg = _localMessages[b];
      msg.isShowCancel = false;
      _localMessages[b] = await _handlerMessage(msg);
    }
    return _localMessages;
  }

  // 处理头像昵称
  Future<ImMessage> _handlerMessage(ImMessage msg) async{
    const String defaultAvatar = 'http://qiniu.cmp520.com/avatar_default.png';
    msg.avatar = defaultAvatar;
    // 消息是我发的
    if(msg.fromAccount == _imUser.id){
      /// 这里如果是接入业务平台可替换成用户头像和昵称
      /// if (uid == myUid)  msg.avatar = MyAvatar
      /// if (uid == myUid)  msg.nickname = MyNickname
      msg.nickname = "我";
    }else{
      if(_serviceUser != null && _serviceUser.id == msg.fromAccount){
        msg.nickname = _serviceUser.nickname ?? "客服";
        msg.avatar = _serviceUser.avatar != null && _serviceUser.avatar.isNotEmpty ? _serviceUser.avatar : defaultAvatar;
      }else{
        String _localServiceUserStr = _prefs.getString("service_user_" + msg.fromAccount.toString());
        if(_localServiceUserStr != null){
          CustomerService _localServiceUser = CustomerService.fromJson(json.decode(_localServiceUserStr));
          msg.nickname = _localServiceUser.nickname ?? "客服";
          msg.avatar = _localServiceUser.avatar != null && _localServiceUser.avatar.isNotEmpty ? _localServiceUser.avatar : defaultAvatar;
        }else if(_robot != null && _robot.id == msg.fromAccount){
          msg.nickname = _robot.nickname ?? "客服";
          msg.avatar = _robot.avatar != null && _robot.avatar.isNotEmpty ? _robot.avatar : defaultAvatar;
        }else{
          String _localRobotStr = _prefs.getString("robot_" + msg.fromAccount.toString());
          if(_localRobotStr != null){
            Robot _localRobot = Robot.fromJson(json.decode(_localRobotStr));
            msg.nickname = _localRobot.nickname ?? "机器人";
            msg.avatar = _localRobot.avatar != null && _localRobot.avatar.isNotEmpty ? _localRobot.avatar : defaultAvatar;
          }else{
            msg.nickname ="未知";
            msg.avatar = defaultAvatar;
          }
        }
      }

    }
    return msg;
  }

  /// 创建消息
  /// [toAccount] 接收方账号
  /// [msgType]   消息类型
  /// [content]   消息内容
  MessageHandle _createMessage({int toAccount, String msgType, dynamic content}){
    MIMCMessage message = MIMCMessage();
    String millisecondsSinceEpoch = DateTime.now().millisecondsSinceEpoch.toString();
    print(millisecondsSinceEpoch);
    int timestamp = int.parse(millisecondsSinceEpoch.substring(0, millisecondsSinceEpoch.length - 3));
    message.timestamp = timestamp;
    message.bizType = msgType;
    message.toAccount = toAccount.toString();
    Map<String, dynamic> payloadMap = {
      "from_account": _imUser.id,
      "to_account": toAccount,
      "biz_type": msgType,
      "version": "0",
      "key": DateTime.now().millisecondsSinceEpoch,
      "platform": Platform.isAndroid ? 6 : 2,
      "timestamp": timestamp,
      "read": 0,
      "transfer_account": 0,
      "payload": content
    };
    message.payload = base64Encode(utf8.encode(json.encode(payloadMap)));
    return MessageHandle(
        sendMessage: message,
        localMessage: ImMessage.fromJson(payloadMap)..isShowCancel = true
    );
  }

  /// 点击发送按钮
  void _onSubmit(){
    String content = _editingController.value.text.trim();
    if(content.isEmpty) return;
    MessageHandle messageHandle =  _createMessage(toAccount: _toAccount, msgType: "text", content: content);
    _sendMessage(messageHandle);
    _cachePushMessage(messageHandle.localMessage);
    _editingController.clear();
  }

  /// 发送消息
  void _sendMessage(MessageHandle msgHandle) async{
    _flutterMimc.sendMessage(msgHandle.sendMessage);
    /// 消息入库（远程）
    MessageHandle cloneMsgHandle = msgHandle.clone();
    String type = cloneMsgHandle.localMessage.bizType;
    if(type == "contacts" || type == "pong" || type == "welcome" || type == "cancel" || type == "handshake") return;
    cloneMsgHandle.sendMessage.toAccount = _robot.id.toString();
    cloneMsgHandle.sendMessage.payload = ImMessage(
      bizType: "into",
      payload: cloneMsgHandle.localMessage.toBase64(),
    ).toBase64();
    _flutterMimc.sendMessage(cloneMsgHandle.sendMessage);
    await Future.delayed(Duration(milliseconds: 10000));
    msgHandle.localMessage.isShowCancel = false;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if(mounted){
      _focusNode.addListener((){
        if(_focusNode.hasFocus){
          _onHideEmoJiPanel();
          _hideFileButtons();
          _toScrollEnd();
        }
      });
      _init();
    }
  }

  /// Scroll to end
  void _toScrollEnd() async{
    await Future.delayed(Duration(milliseconds: 100));
    _scrollController.jumpTo(0);
  }

  /// onShowEmoJiPanel
  void _onShowEmoJiPanel() async{
    FocusScope.of(context).requestFocus(FocusNode());
    await Future.delayed(Duration(milliseconds: 100));
    setState(() {
      _isShowEmoJiPanel = true;
    });
    _hideFileButtons();
  }

  /// onHideEmoJiPanel
  void _onHideEmoJiPanel(){
    setState(() {
      _isShowEmoJiPanel = false;
    });
  }

  @override
  void dispose(){
    _focusNode?.dispose();
    _editingController?.dispose();
    _subStatus?.cancel();
    _subHandleMessage?.cancel();
    super.dispose();
  }

  /// EmoJiPanel
  Widget _emoJiPanel(){
    return EmoJiPanel(isShow: _isShowEmoJiPanel, onSelected: (String emoji){
      _editingController.text = _editingController.value.text + emoji;
    },);
  }


  ///  接入人工 or 结束会话
  bool _isOnHeadRightButton = false;
  _onHeadRightButton() async{
    if(_isOnHeadRightButton) return;
    _isOnHeadRightButton = true;
    if(_isCustomerService){
      ImUtils.alert(context, content: "您是否确认关闭本次会话？", onConfirm: (){
        MessageHandle msgHandle =  _createMessage(toAccount: _toAccount, msgType: "end", content: "");
        _sendMessage(msgHandle);
        _cachePushMessage(msgHandle.localMessage);
        _isCustomerService = null;
        _isCustomerService = false;
        setState(() {});
      });
      await Future.delayed(Duration(milliseconds: 1000));
      _isOnHeadRightButton = false;
      return;
    }
    _editingController.text = "人工";
    _onSubmit();
    setState(() {});
    await Future.delayed(Duration(milliseconds: 1000));
    _isOnHeadRightButton = false;
  }

  /// 显示文件面板
  void _showFileButtons(){
    _isShowFileButtons = true;
    _onHideEmoJiPanel();
    FocusScope.of(context).requestFocus(FocusNode());
    setState(() {});
  }
  /// 隐藏文件面板
  void _hideFileButtons(){
    _isShowFileButtons = false;
    setState(() {});
  }

  /// 选择图片文件
  void _getImage(ImageSource source) async {
    _hideFileButtons();
    File _file = await ImagePicker.pickImage(source: source, maxWidth: 2000);
    if(_file == null) return;
    _sendPhoto(_file);
  }

  /// 上传
  void _sendPhoto(File file) async{
    try {
      if(file ==null) return;
      MessageHandle msgHandle =  _createMessage(toAccount: _toAccount, msgType: "photo", content: file.path);
      _cachePushMessage(msgHandle.localMessage..isShowCancel = false);
      String filePath = file.path;
      String fileName = "${DateTime.now().microsecondsSinceEpoch}_" + (filePath.lastIndexOf('/') > -1 ? filePath.substring(filePath.lastIndexOf('/') + 1) : filePath);

      /// 七牛上传
      if(_uploadSecret.mode == 1){
        FormData formData = new FormData.from({
          "fileType": "image",
          "fileName": "file",
          "key": fileName,
          "token": _uploadSecret.secret,
          "file": UploadFileInfo(file,fileName)
        });
        Response response = await _http.post("https://upload.qiniup.com", data: formData, onSendProgress: (int sent, int total){
          msgHandle.localMessage.uploadProgress = (sent/total*100).ceil();
          setState(() {});
        });
        if(response.statusCode == 200){
          msgHandle.localMessage.isShowCancel = true;
          setState(() {});
          String img = _uploadSecret.host + "/" + response.data["key"];
          ImMessage sendMsg = ImMessage.fromJson(json.decode(utf8.decode(base64Decode(msgHandle.sendMessage.payload))));
          sendMsg.payload = img;
          msgHandle.sendMessage.payload = base64Encode(utf8.encode(json.encode(sendMsg.toJson())));
          _sendMessage(msgHandle.clone()..localMessage.payload = img);
          await Future.delayed(Duration(milliseconds: 10000));
          msgHandle.localMessage.isShowCancel = false;
          setState(() {});
        }else{
          _deleteMessage(msgHandle.localMessage);
          ImUtils.alert(context, content: "图片上传失败！");
        }
      }else{
        /// 其他
      }

    }catch(e){
      ImUtils.alert(context, content: "图片上传失败！");
      debugPrint(e);
    }

  }

  // 操作消息
  void _onMessageOperation(ImMessage message) {
    bool isLocalImage = message.payload != null && !message.payload.contains(RegExp(r'^(http://|https://)'));
    bool isPhoto = message.bizType == "photo";
    Widget _delete(){
      return CupertinoDialogAction(
        child: const Text('删除'),
        onPressed: () {
          _deleteMessage(message);
          Navigator.pop(context);
        },
      );
    }

    Widget _cancel(){
      return CupertinoDialogAction(
        child: const Text('撤回'),
        onPressed: () {
          _onCancelMessage(message);
          Navigator.pop(context);
        },
      );
    }

    Widget _close(){
      return CupertinoDialogAction(
        child: const Text('取消'),
        isDestructiveAction: true,
        onPressed: () {
          Navigator.pop(context);
        },
      );
    }

    Widget _copy(){
      return CupertinoDialogAction(
        child: Text(isPhoto ? "复制图片链接" : '复制'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message.payload));
          Navigator.pop(context);
          ImUtils.alert(context, content: "消息已复制到粘贴板");
        },
      );
    }

    List<Widget> actions = [];
    if(message.isShowCancel) actions.add(_cancel());
    actions.add(_delete());
    if(message.bizType == "text") actions.add(_copy());
    if(isPhoto && !isLocalImage){
      actions.add(_copy());
    }
    actions.add(_close());

    showCupertinoDialog(context: context, builder: (_){
      return CupertinoAlertDialog(
          title: Text('消息操作', style: TextStyle(
            color: Colors.black.withAlpha(150),
            fontSize: 14.0
          ),),
          content:isPhoto ? SizedBox(
            width: 100.0,
            height:  100.0,
            child: CachedImage(
                width:  100.0,
                height:  100.0,
                bgColor: Colors.transparent,
                fit: BoxFit.contain,
                src: "${message.payload}"
            ),
          ) : Text(message.payload, maxLines: 8, overflow: TextOverflow.ellipsis, style: TextStyle(
            height: 1.5,
            color: Colors.black87
          ),),
          actions: actions
      );
    });
  }

  // 撤回一条消息
  void _onCancelMessage(ImMessage msg){
    if(!msg.isShowCancel){
      ImUtils.alert(context, content: "已超过撤回时间！");
      return;
    }
    MessageHandle msgHandle =  _createMessage(toAccount: _toAccount, msgType: "cancel", content: msg.key);
    _sendMessage(msgHandle);
    _cachePushMessage(msgHandle.localMessage);
    _deleteMessage(msg);
  }

  /// 删除消息
  void _deleteMessage(ImMessage msg){
    int index = _messagesRecord.indexWhere((i) => i.key == msg.key && i.fromAccount == msg.fromAccount);
    _messagesRecord.removeAt(index);
    List<String> _messages =_prefs.getStringList("miniImAppMessageRecord_${_imUser.id}");
    if(_messages != null){
      int _messageIndex;
      for(var i =0; i<_messages.length; i++){
        ImMessage m = ImMessage.fromJson(json.decode(_messages[i]));
        if(m.key == msg.key){
          _messageIndex = i;
          break;
        }
      }
      _messages.removeAt(_messageIndex);
      _prefs.setStringList("miniImAppMessageRecord_${_imUser.id}", _messages);
    }
    setState(() {});
  }

  // 消息内容变
  bool isSendPong = false;
  void _inputOnChanged(String value) async{
     if(!_isCustomerService || isSendPong) return;
     isSendPong = true;
      String content = _editingController.value.text.trim();
     MessageHandle _msgHandle =  _createMessage(toAccount: _toAccount, msgType: "pong", content: content);
     _sendMessage(_msgHandle);
     await Future.delayed(Duration(milliseconds: 200));
     isSendPong = false;
  }


  /// footer bar
  Widget _bottomBar(){
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal:10.0, vertical: 5.0),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.withAlpha(60), width: .5),
            bottom: BorderSide(color: Colors.grey.withAlpha(_isShowEmoJiPanel ? 60 : 0), width: .5),
          )
      ),
      constraints: BoxConstraints(
        minHeight: 80.0,
      ),
      child: Column(
        children: <Widget>[
          Offstage(
            offstage: !_isShowFileButtons,
            child: Column(
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 10.0),
                  color: Colors.white,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      GestureDetector(
                          onTap: () => _getImage(ImageSource.gallery),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Container(
                                margin: EdgeInsets.only(bottom: 3.0),
                                padding: EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.all(Radius.circular(5.0))
                                ),
                                child: Icon(Icons.image, color: Colors.white,),
                              ),
                              Text("相册", style: TextStyle(color: Colors.black54, fontSize: 13.0),)
                            ],
                          )
                      ),
                      VerticalDivider(width: 15.0,color: Colors.transparent,),
                      GestureDetector(
                          onTap: () => _getImage(ImageSource.camera),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Container(
                                margin: EdgeInsets.only(bottom: 3.0),
                                padding: EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.all(Radius.circular(5.0))
                                ),
                                child: Icon(Icons.camera_alt, color: Colors.white,),
                              ),
                              Text("相机", style: TextStyle(color: Colors.black54, fontSize: 13.0),)
                            ],
                          )
                      ),
                    ],
                  ),
                ),
                Divider()
              ],
            ),
          ),
          SizedBox(
            child: Row(
              children: <Widget>[
                GestureDetector(
                    child: Container(
                      padding: EdgeInsets.all(3.0),
                      child: Icon(Icons.add_circle_outline, color: Colors.black26, size: 25,),
                    ),
                    onTap: _isShowFileButtons ? _hideFileButtons : _showFileButtons
                ),
                GestureDetector(
                    child: Padding(
                      padding: EdgeInsets.all(3.0),
                      child: Icon(Icons.insert_emoticon, color: Colors.black26, size: 25,),
                    ),
                    onTap: _isShowEmoJiPanel ? _onHideEmoJiPanel : _onShowEmoJiPanel
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                  child: Container(
                      constraints: BoxConstraints(
                          minHeight: 50.0
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 5.0),
                      child: TextField(
                        cursorColor: Colors.transparent,
                        decoration: InputDecoration(
                            hintText: "请用一句话描述您的问题~",
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                              color: Colors.grey.withAlpha(150),
                            ),
                            counterStyle: TextStyle(color: Colors.grey.withAlpha(200)),
                            contentPadding: EdgeInsets.symmetric(vertical: 3.0),
                            counterText: ""
                        ),
                        style: TextStyle(
                            color: Colors.black.withAlpha(170)
                        ),
                        focusNode: _focusNode,
                        controller: _editingController,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 200,
                        textInputAction: TextInputAction.newline,
                        onChanged: (String value) => _inputOnChanged(value),
                      )
                  )
              ),
              Center(
                child: SizedBox(
                  width: 60.0,
                  child: FlatButton(
                    color: Theme.of(context).primaryColor,
                    onPressed: _onSubmit,
                    child: Text("发送", style: TextStyle(color: Colors.white),),
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_isPong ? "对方正在输入..." : '在线客服'),
        actions: <Widget>[
          _isCustomerService ?
          FlatButton(
            child: Text("结束会话", style: TextStyle(color: Colors.white),),
            onPressed: _onHeadRightButton,
          ) :
          IconButton(
            icon: Icon(Icons.face, size: 25.0,),
            onPressed: _onHeadRightButton,
          )
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onPanDown: (_){
                _onHideEmoJiPanel();
                _hideFileButtons();
                FocusScope.of(context).requestFocus(FocusNode());
              },
              child: CustomScrollView(
                controller: _scrollController,
                reverse: true,
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 20.0),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((ctx, i){

                          int index = _messagesRecord.length - i - 1;
                          ImMessage  _msg = _messagesRecord[index];

                           /// 判断是否需要显示时间
                          bool isShowDate = false;
                          if(i == _messagesRecord.length-1 || (_msg.timestamp-120) > _messagesRecord[index-1].timestamp){
                            isShowDate = true;
                          }

                          switch(_msg.bizType){
                            case "text":
                            case "welcome":
                              return TextMessage(
                                message: _msg,
                                isShowDate: isShowDate,
                                isSelf: _msg.fromAccount == _imUser.id,
                                onCancel: () =>  _onCancelMessage(_msg),
                                onOperation: () => _onMessageOperation(_msg),
                              );
                            case "photo":
                              return PhotoMessage(message: _msg,
                                isShowDate: isShowDate,
                                isSelf: _msg.fromAccount == _imUser.id,
                                onCancel: () =>  _onCancelMessage(_msg),
                                onOperation: () =>  _onMessageOperation(_msg),
                              );
                            case "end":
                            case "transfer":
                            case "cancel":
                            case "timeout":
                            case "system":
                              return SystemMessage(
                                message: _msg,
                                isSelf: _msg.fromAccount == _imUser.id,
                              );
                            case "knowledge":
                              return KnowledgeMessage(message: _msg, isShowDate: isShowDate, onSend: (msg){
                                _editingController.text = msg.title == "以上都不是？我要找人工" ? "人工" : msg.title;
                                _onSubmit();
                              },);
                            default:
                              return SizedBox();
                          }
                        },childCount: _messagesRecord.length)
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Offstage(
                      offstage: !_isMorLoading,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.0),
                        child:  Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            SizedBox(
                                width: 10.0,
                                height: 10.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                )
                            ),
                            Text("  加载更多", style: TextStyle(color: Colors.black38),)
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            child:  SafeArea(
              top: false,
              child: Column(
                children: <Widget>[
                  _bottomBar(),
                  _emoJiPanel(),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

/// 创建一条消息
///  [sendMessage] 发送对象
///  [imMessage]  本地显示对象
class MessageHandle{
  MessageHandle({this.sendMessage, this.localMessage});
  MIMCMessage sendMessage;
  ImMessage localMessage;
  MessageHandle clone(){
    return MessageHandle(
      sendMessage: MIMCMessage.fromJson(sendMessage.toJson()),
      localMessage: ImMessage.fromJson(localMessage.toJson()),
    );
  }
}