import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  await Hive.openBox('messages');
  runApp(NearbyChatApp());
}

class NearbyChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دردشة قريبة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: NearbyChatPage(),
    );
  }
}

class NearbyChatPage extends StatefulWidget {
  @override
  _NearbyChatPageState createState() => _NearbyChatPageState();
}

class _NearbyChatPageState extends State<NearbyChatPage> {
  final Strategy strategy = Strategy.P2P_STAR;
  final String serviceId = "com.canaryweb.flutter_application_7";
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker picker = ImagePicker();
  final AudioPlayer audioPlayer = AudioPlayer();

  String? connectedEndpointId;
  String connectedDeviceName = "";
  bool isConnected = false;
  bool isAdvertising = false;
  bool isDiscovering = false;
  int rssiValue = -60; // قيمة افتراضية لمؤشر قوة الإشارة

  List<Map<String, dynamic>> messages = [];
  List<Map<String, String>> discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _askPermissions();
    _loadMessages();
  }

  Future<void> _askPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  Future<void> _loadMessages() async {
    final box = Hive.box('messages');
    final stored = box.get('chats', defaultValue: []);
    setState(() => messages = List<Map<String, dynamic>>.from(stored));
  }

  Future<void> _saveMessages() async {
    final box = Hive.box('messages');
    await box.put('chats', messages);
  }

  void _addMessage(String text, bool isMine, {bool isImage = false}) {
    final msg = {
      "text": text,
      "isMine": isMine,
      "isImage": isImage,
      "time": TimeOfDay.now().format(context),
    };
    setState(() {
      messages.add(msg);
    });
    _saveMessages();
  }

  void _addSystemMessage(String text) {
    final msg = {
      "text": text,
      "isMine": null,
      "time": TimeOfDay.now().format(context),
    };
    setState(() {
      messages.add(msg);
    });
  }

  /// ====== تشغيل الصوت عند استقبال رسالة ======
  Future<void> _playNotificationSound() async {
    await audioPlayer.play(AssetSource('assets/notification.mp3'));
  }

  /// ====== Advertising ======
  Future<void> startAdvertising() async {
    setState(() => isAdvertising = true);
    await Nearby().startAdvertising(
      "جهازي",
      strategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedEndpointId = id;
            connectedDeviceName = id;
            isConnected = true;
          });
          _addSystemMessage("✅ تم الاتصال بـ $id");
        } else {
          _addSystemMessage("❌ فشل الاتصال");
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedEndpointId = null;
          connectedDeviceName = "";
          isConnected = false;
        });
        _addSystemMessage("⚠️ تم فصل الاتصال");
      },
      serviceId: serviceId,
    );
  }

  /// ====== Discovery ======
  Future<void> startDiscovery() async {
    setState(() => isDiscovering = true);
    await Nearby().startDiscovery(
      "باحث",
      strategy,
      onEndpointFound: (id, name, serviceId) {
        setState(() {
          discoveredDevices.add({"id": id, "name": name});
        });
        _addSystemMessage("🔍 تم العثور على جهاز: $name");
      },
      onEndpointLost: (id) {
        setState(() {
          discoveredDevices.removeWhere((e) => e["id"] == id);
        });
      },
      serviceId: serviceId,
    );
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    // استخدام قيمة افتراضية للـ RSSI
    rssiValue = -60;

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.bytes != null) {
          final text = utf8.decode(payload.bytes!);
          if (text.startsWith("IMG:")) {
            _addMessage(text.substring(4), false, isImage: true);
          } else {
            _addMessage(text, false);
          }
          _playNotificationSound(); // 🔔 صوت مبتكر
        }
      },
    );
  }

  Future<void> requestConnection(String id, String name) async {
    await Nearby().requestConnection(
      name,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedEndpointId = id;
            connectedDeviceName = name;
            isConnected = true;
          });
          _addSystemMessage("✅ تم الاتصال بـ $name");
        } else {
          _addSystemMessage("❌ فشل الاتصال");
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedEndpointId = null;
          connectedDeviceName = "";
          isConnected = false;
        });
        _addSystemMessage("⚠️ تم فصل الاتصال");
      },
    );
  }

  /// ====== إرسال نص ======
  Future<void> sendMessage() async {
    if (connectedEndpointId == null) {
      _addSystemMessage("⚠️ لا يوجد اتصال");
      return;
    }
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final bytes = Uint8List.fromList(utf8.encode(text));
    await Nearby().sendBytesPayload(connectedEndpointId!, bytes);
    _addMessage(text, true);
    _messageController.clear();
  }

  /// ====== إرسال صورة ======
  Future<void> sendImage() async {
    if (connectedEndpointId == null) {
      _addSystemMessage("⚠️ لا يوجد اتصال لإرسال الصورة");
      return;
    }

    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    final encoded = base64Encode(bytes);

    await Nearby().sendBytesPayload(
      connectedEndpointId!,
      Uint8List.fromList(utf8.encode("IMG:$encoded")),
    );

    // ✅ حفظ الصورة في نفس الجهاز أيضًا
    _addMessage(encoded, true, isImage: true);
  }

  /// ====== عرض الصورة بشكل آمن ======
  Widget _buildImageBubble(String data, bool isMine) {
    try {
      final bytes = base64Decode(data);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Icon(
            Icons.broken_image,
            color: isMine ? Colors.white : Colors.black54,
            size: 60,
          ),
        ),
      );
    } catch (e) {
      return Text(
        "⚠️ خطأ في عرض الصورة",
        style: TextStyle(color: isMine ? Colors.white : Colors.black),
      );
    }
  }

  /// ====== مؤشر قوة الإشارة ======
  Widget _signalIndicator() {
    Color color;
    String status;

    if (rssiValue > -50) {
      color = Colors.blue;
      status = "🔵 قريب جدًا";
    } else if (rssiValue > -70) {
      color = Colors.green;
      status = "🟢 قريب";
    } else if (rssiValue > -85) {
      color = Colors.orange;
      status = "🟠 متوسط";
    } else {
      color = Colors.red;
      status = "🔴 بعيد";
    }

    return Row(
      children: [
        Icon(Icons.signal_cellular_alt, color: color),
        SizedBox(width: 5),
        Text(status, style: TextStyle(color: color)),
      ],
    );
  }

  /// ====== واجهة المستخدم ======
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: Colors.blueAccent,
          title: Row(
            children: [
              Icon(Icons.chat_bubble_outline, color: Colors.white),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'دردشة قريبة',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  Row(
                    children: [
                      Text(
                        isConnected
                            ? "متصل بـ $connectedDeviceName"
                            : "غير متصل",
                        style: TextStyle(
                          color: isConnected
                              ? Colors.greenAccent
                              : Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      if (isConnected) SizedBox(width: 8),
                      if (isConnected) _signalIndicator(),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.wifi_tethering, color: Colors.white),
              tooltip: "بدء الإرسال",
              onPressed: startAdvertising,
            ),
            IconButton(
              icon: Icon(Icons.search, color: Colors.white),
              tooltip: "البحث عن الأجهزة",
              onPressed: startDiscovery,
            ),
          ],
        ),
        body: Column(
          children: [
            if (discoveredDevices.isNotEmpty && connectedEndpointId == null)
              Container(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = discoveredDevices[index];
                    return Card(
                      margin: EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(device["name"] ?? ""),
                            ElevatedButton(
                              onPressed: () => requestConnection(
                                device["id"]!,
                                device["name"]!,
                              ),
                              child: Text("اتصال"),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: EdgeInsets.all(8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages.reversed.toList()[index];
                  final isMine = msg["isMine"];
                  final isImage = msg["isImage"] ?? false;

                  if (isMine == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          msg["text"],
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: isMine
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.blueAccent.withOpacity(0.8)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: isImage
                          ? _buildImageBubble(msg["text"], isMine)
                          : Text(
                              msg["text"],
                              style: TextStyle(
                                color: isMine ? Colors.white : Colors.black87,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.image, color: Colors.blue),
                    onPressed: sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: "اكتب رسالتك...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: Colors.blue),
                    onPressed: sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
