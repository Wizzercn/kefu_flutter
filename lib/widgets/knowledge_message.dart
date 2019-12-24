import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/im_utils.dart';
import '../models/im_message.dart';
import '../models/knowledge_model.dart';
import 'im_avatar.dart';

typedef SendKnowledgeMessage(KnowledgeModel message);
class KnowledgeMessage extends StatelessWidget{
  KnowledgeMessage({this.message, this.onSend});
  final ImMessage message;
  final SendKnowledgeMessage onSend;
  bool get isSelf{
    return true;
  }
  List<KnowledgeModel> get knowledgeModelList => (json.decode(message.payload) as List).map((i)=>KnowledgeModel.fromJson(i)).toList();
  @override
  Widget build(BuildContext context) {
    int index = 0;
    return Container(
      margin: EdgeInsets.only(bottom: 15.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          ImAvatar(avatar: message.avatar,),
          Padding(
            padding: EdgeInsets.only(left: 7.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                    children: [
                      Text('${message.nickname}', style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16.0,
                          color: Colors.black.withAlpha(150)
                      )),
                      Text(' ${ImUtils.formatDate(message.timestamp)} ', style: TextStyle(color: Colors.black45) ),
                    ]
                ),
                Container(
                  margin: EdgeInsets.only(top: 3.0),
                  width: 280.0,
                  padding: EdgeInsets.symmetric(horizontal:10.0, vertical: 5.0),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          offset: Offset(0.0, 3.0),
                          color: Colors.black26.withAlpha(5),
                          blurRadius: 4.0,
                        ),
                        BoxShadow(
                          offset: Offset(0.0, 3.0),
                          color: Colors.black26.withAlpha(5),
                          blurRadius: 4.0,
                        ),
                      ],
                      borderRadius: BorderRadius.all(Radius.circular(5))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("以下是您关系的相关问题？", style:  TextStyle(color: Colors.black87.withAlpha(180), fontSize: 16.0)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: knowledgeModelList.map((KnowledgeModel item){
                          index ++;
                          return GestureDetector(
                            onTap: () => onSend(item),
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 15.0
                              ),
                              child:  Padding(
                                padding: EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(" • "),
                                  Expanded(
                                    child: Text("${item.title}"),
                                  )
                                ],
                              ),
                              )
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}