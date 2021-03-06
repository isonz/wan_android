import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import './dialog.dart';
import '../../Api.dart';
import 'package:package_info/package_info.dart';
import '../../widget/T.dart';
import 'package:dio/dio.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:progress_dialog/progress_dialog.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:isolate';

class DownloadPage extends StatefulWidget {
  final Widget child;

  DownloadPage({Key key, this.child}) : super(key: key);

  _DownloadPageState createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {

  ProgressDialog pr;

  ReceivePort _port = ReceivePort();

  String version;

  // 获取当前应用版本
  void GetVersion() {
    PackageInfo.fromPlatform().then((PackageInfo packageInfo) {
      // 得到当前应用版本号
      setState(() {
        version = packageInfo.version;
      });
    });
  }



  // 检查应用是否需要更新版本
  void CheckVersion() async {
    // 显示检查版本更新中对话框
    ProgressDialog pr2 = new ProgressDialog(context);
    pr2.show();
    pr2.update(message: '检查版本更新中');
    // 先获取线上应用的版本信息
    var data;
    var dataKey = {'_api_key': Api.API_KEY, 'appKey': Api.APP_KEY};
    Response response;
    Dio dio = new Dio();
    response = await dio.post(Api.CHECK_VERSION,queryParameters: dataKey);
    data = json.decode(response.toString());
    data = data['data'];      
    // 进行版本号比对
    var checek = version.compareTo(data['buildVersion']);
    // 当前版本小于线上版本就要更新了
    if(checek == -1){
      pr2.hide();
      // 获取线上安装包大小 这里的请求要用 使用application/x-www-form-urlencoded编码 
      // 我搞了半天用 postman 测试了好久，再去 dio 官方文档找了怎么编码才搞定
    response = await dio.post(Api.APP_SIZE,data: dataKey,options: Options(contentType:Headers.formUrlEncodedContentType));
    var dataSize = json.decode(response.toString());
    dataSize = dataSize['data'];
    dataSize = dataSize['buildFileSize'];
    // 计算安装包大小
    int Size = int.parse(dataSize);
    double appSize = Size/1000000;
    String finalSize = appSize.toStringAsFixed(2);
    // 拼接一下更新描述说明
    String description = data['buildUpdateDescription'];
    // 弹出是否更新对话框
      showDialog(
        context: context,
        child: DialogShow(
          title:'确定更新？',
          subTitle: '更新说明：',
          smallSubTitle: '新版本安装包大小为' + finalSize + 'MB',
          description: description, 
          yes: download
          ),
        barrierDismissible: false
      );
    }else {
      T.showToast('已经是最新版本');
    }
  }

  // 初始化
  Future<void> initDownload() async {
    // 初始化下载进度条
    pr = new ProgressDialog(context,type: ProgressDialogType.Download);
  }

  // 更新下载安装
  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) {
      print('UI Isolate Callback: $data');
      String id = data[0];
      DownloadTaskStatus status = data[1];
      int progress = data[2];
      // 下载完成 关闭进度条对话框，打开安装包
      if(status == DownloadTaskStatus.complete){
        T.showToast('下载完成咯');
        pr.hide();
        FlutterDownloader.open(taskId: id);
      }
      // 更新进度条对话框进度
      setState(() {
        pr.update(progress: progress.toDouble(),maxProgress: 100,message: '正在下载中...');
      });
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  // 下载进度监听回调
  static void downloadCallback(
      String id, DownloadTaskStatus status, int progress) {
    print(
        'Background Isolate Callback: task ($id) is in status ($status) and process ($progress)');
    final SendPort send =
        IsolateNameServer.lookupPortByName('downloader_send_port');
    send.send([id, status, progress]);
  }

  // 下载
  Future<void> download() async {
    initDownload();
    // 记得下载之前一定要申请存储权限，而且在 main 目录下的 AndroidManifest 中加配置，不然不行
    _checkPermission();
    // 获取文件存储路径，记得去 AndroidManifest 配置，注意这里只写了安卓的，iOS 需要另外判断
    Directory appDocDir = await getExternalStorageDirectory();
    String appDocPath = appDocDir.path;
    final taskId = await FlutterDownloader.enqueue(
      url: Api.INSTALL + '?_api_key=' + Api.API_KEY + '&appKey='+ Api.APP_KEY,
      savedDir: appDocPath,
      showNotification: true, // show download progress in status bar (for Android)
      openFileFromNotification: true, // click on notification to open downloaded file (for Android)
      fileName: 'aaa.apk'
    );
    await pr.show();
  }

  // 申请权限
  Future<bool> _checkPermission() async {
    await Permission.storage.request();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _bindBackgroundIsolate();
    // 初始化进度条对话框
    initDownload();
    // 注册下载监听回调
    FlutterDownloader.registerCallback(downloadCallback);
    // 获取当前版本
    GetVersion();
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: (){
        CheckVersion();
      },
      leading: Icon(Icons.system_update,color: Theme.of(context).primaryColor),
      title: Text('检查更新',style: TextStyle(color: Theme.of(context).primaryColor),),
      subtitle: Text('当前版本 $version',style: TextStyle(fontSize: 12),),
    );
  }
}