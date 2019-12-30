import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_advanced_networkimage/zoomable.dart';
import '../models/im_message.dart';
import 'cached_network_image.dart';
import 'date_widget.dart';
import 'im_avatar.dart';

class PhotoMessage extends StatelessWidget {
  PhotoMessage({this.message, this.onCancel, this.onOperation, this.isSelf});
  final ImMessage message;
  final VoidCallback onCancel;
  final VoidCallback onOperation;
  final bool isSelf;
  @override
  Widget build(BuildContext context) {
    Widget _avatar(bool show) {
      return Offstage(
          offstage: !show,
          child: ImAvatar(
            avatar: message.avatar,
          ));
    }

    Widget _loading() {
      return SizedBox(
        width: 10.0,
        height: 10.0,
        child: Platform.isAndroid
            ? CircularProgressIndicator(
                strokeWidth: 2.0,
              )
            : CupertinoActivityIndicator(
                radius: 8.0,
              ),
      );
    }

    Widget _state() {
      return Offstage(
        offstage: !isSelf,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Offstage(
              offstage: !message.isShowCancel,
              child: GestureDetector(
                onTap: onCancel,
                child: Text(" 撤回 ", style: TextStyle(color: Colors.blue)),
              ),
            ),
            Offstage(
              offstage:
                  message.uploadProgress == 0 || message.uploadProgress == 100,
              child: Row(
                children: <Widget>[
                  _loading(),
                  Text(
                    " ${message.uploadProgress}%  ",
                    style: TextStyle(color: Colors.black26),
                  ),
                ],
              ),
            )
          ],
        ),
      );
    }

    Widget msgWidget() {
      return Container(
        margin: EdgeInsets.only(bottom: 15.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: <Widget>[
            _avatar(!isSelf),
            Padding(
              padding: EdgeInsets.only(
                  left: isSelf ? 0 : 7.0, right: isSelf ? 7.0 : 0),
              child: Column(
                crossAxisAlignment:
                    isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _state(),
                      Hero(
                          tag: message.payload,
                          child: GestureDetector(
                              onLongPress: onOperation,
                              onTap: () {
                                showDialog(
                                    context: context,
                                    builder: (context) {
                                      return Center(
                                          child: ZoomableWidget(
                                        onTap: () => Navigator.pop(context),
                                        maxScale: 2.0,
                                        minScale: 0.5,
                                        child: CachedImage(
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width /
                                                1,
                                            height: MediaQuery.of(context)
                                                    .size
                                                    .height /
                                                1,
                                            src: message.payload,
                                            bgColor: Colors.transparent,
                                            fit: BoxFit.fitWidth),
                                      ));
                                    });
                              },
                              child: Container(
                                margin: EdgeInsets.only(top: 3.0),
                                constraints: BoxConstraints(
                                  maxWidth: 200.0,
                                ),
                                child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(5.0)),
                                    child: CachedImage(
                                        width: 150.0,
                                        height: 180.0,
                                        bgColor: Colors.white,
                                        src: message.payload,
                                        fit: BoxFit.fitWidth)),
                              ))),
                    ],
                  )
                ],
              ),
            ),
            _avatar(isSelf),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        Offstage(
          offstage: !message.isShowDate,
          child: DateWidget(
            date: message.timestamp,
          ),
        ),
        msgWidget()
      ],
    );
  }
}
