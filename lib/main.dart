import 'dart:convert';
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MaterialApp(home: MemoPage()));
}

class MemoPage extends StatefulWidget {
  const MemoPage({super.key});

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker(); 
  
  List<Map<String, String>> _memoList = [];
  String _uploadedImageUrl = ''; 
  bool _isUploading = false;     

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 💾 データを保存する関数
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_memoList);
    await prefs.setString('memo_with_imgbb_v1_key', jsonString);
  }

  // 📂 データを読み込む関数
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('memo_with_imgbb_v1_key');
    if (jsonString != null) {
      setState(() {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _memoList = decoded.map((item) => Map<String, String>.from(item)).toList();
      });
    }
  }

  // 🚀 写真をインターネット倉庫（ImgBB）にアップロードする関数
  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isUploading = true; 
    });

    try {
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64Body = base64Encode(imageBytes);

      final Uri url = Uri(
        scheme: 'https',
        host: '://imgbb.com',
        path: '/1/upload',
      );
      
      final response = await http.post(
        url,
        body: {
          'key': 'f4b3e12ae146cf9e2c030c3d74e4a4d6', // 🔑 あなた専用のAPIキーを入れてください！
          'image': base64Body,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body);
        setState(() {
          _uploadedImageUrl = jsonMap['data']['url'];
        });
      } else {
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('アップロード失敗（診断）'),
            content: Text('ステータスコード: ${response.statusCode}\n\nサーバーからの返答:\n${response.body}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('通信エラー（診断）'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } finally {
      setState(() {
        _isUploading = false; 
      });
    }
  }

  // 🔍 写真を大きく表示する（ポップアップ）関数
  void _showLargeImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(imageUrl, fit: BoxFit.contain),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  // 🗑️ 【新機能】削除を確認するポップアップ画面を表示する関数
  void _showDeleteConfirmDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('メモの削除確認'),
          content: const Text('このメモを本当に削除してもよろしいですか？\n削除したメモは元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // 「いいえ」で閉じる
              child: const Text('いいえ', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _memoList.removeAt(index)); // 実際に消す
                _saveData(); // 保存する
                Navigator.pop(context); // 閉じる
              },
              child: const Text('はい', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('無限保存・クラウドメモ'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _controller, 
              decoration: const InputDecoration(hintText: 'メモを入力してください'),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _isUploading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _pickAndUploadImage,
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('写真をクラウドに保存'),
                      ),
                const SizedBox(width: 15),
                _uploadedImageUrl.isNotEmpty
                    ? Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                        child: Image.network(_uploadedImageUrl, fit: BoxFit.cover),
                      )
                    : const Text('写真なし', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 15),

            ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  final now = DateTime.now();
                  final String formattedDate = 
                      '${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}';

                  setState(() {
                    _memoList.add({
                      'text': _controller.text,
                      'date': formattedDate,
                      'image': _uploadedImageUrl, 
                    });
                    _uploadedImageUrl = ''; 
                  });
                  _saveData();
                  _controller.clear();
                }
              },
              child: const Text('クラウドメモを追加'),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _memoList.isEmpty
                  ? const Center(child: Text('まだ履歴はありません'))
                  : ListView.builder(
                      itemCount: _memoList.length,
                      itemBuilder: (context, index) {
                        final String? imageUrlStr = _memoList[index]['image'];
                        
                        return Card(
                          // 💡 改善ポイント①：背景色を濃いグレーから、目に優しい「超淡いブルーグレー」に変えました！
                          color: const Color(0xFFF0F4F8), 
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          child: ListTile(
                            leading: imageUrlStr != null && imageUrlStr.isNotEmpty
                                ? GestureDetector(
                                    onTap: () => _showLargeImage(imageUrlStr), 
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
                                      child: Image.network(imageUrlStr, fit: BoxFit.cover),
                                    ),
                                  )
                                // 💡 改善ポイント②：アイコンの色を白から、淡い背景に映える「青グレー」に変えて見やすくしました！
                                : const Icon(Icons.note, size: 40, color: Colors.blueGrey), 
                            
                            // 💡 改善ポイント③：文字色を「黒」に指定し、パッと一瞬で読めるようにしました！
                            title: Text(_memoList[index]['text'] ?? '', style: const TextStyle(fontSize: 18, color: Colors.black)),
                            subtitle: Text(_memoList[index]['date'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                // 💡 改善ポイント④：いきなり消さず、確認ポップアップを呼び出すように変更！
                                _showDeleteConfirmDialog(index); 
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
