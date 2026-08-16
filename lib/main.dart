import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // 💡 新しい写真部品
import 'package:shared_preferences/shared_preferences.dart';

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
  final ImagePicker _picker = ImagePicker(); // 写真を選ぶためのリモコン
  
  List<Map<String, String>> _memoList = [];
  String _selectedImageBase64 = ''; // 💡 選択された写真を一時的に保存する箱

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 💾 データを保存する関数
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_memoList);
    await prefs.setString('memo_with_image_key', jsonString);
  }

  // 📂 データを読み込む関数
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('memo_with_image_key');
    if (jsonString != null) {
      setState(() {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _memoList = decoded.map((item) => Map<String, String>.from(item)).toList();
      });
    }
  }

  // 📸 写真をアルバムから選択する関数
  Future<void> _pickImage() async {
    // アルバムから写真を選びます（Webアプリでは自動で写真ファイルが開きます）
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // 写真データをネット保存用の文字（Base64）に変換します
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImageBase64 = base64Encode(bytes);
      });
    }
  }

  // 🔍 写真を大きく表示する（ポップアップ）関数
  void _showLargeImage(String base64Image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 💡 文字データから画像を復元して大きく表示
            Image.memory(base64Decode(base64Image), fit: BoxFit.contain),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写真も残せるメモアプリ'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 入力欄
            TextField(
              controller: _controller, 
              decoration: const InputDecoration(hintText: 'メモを入力してください'),
            ),
            const SizedBox(height: 10),

            // 【新機能】写真を選ぶ・確認するエリア
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('写真を追加'),
                ),
                const SizedBox(width: 15),
                // 💡 写真が選ばれていたら、横に小さな確認画面（サムネイル）を出します
                _selectedImageBase64.isNotEmpty
                    ? Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                        child: Image.memory(base64Decode(_selectedImageBase64), fit: BoxFit.cover),
                      )
                    : const Text('写真なし', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 15),

            // 追加ボタン
            ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  final now = DateTime.now();
                  final String formattedDate = 
                      '${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}';

                  setState(() {
                    // 💡 テキスト、日付と一緒に「写真データ（image）」もペアにして保存します
                    _memoList.add({
                      'text': _controller.text,
                      'date': formattedDate,
                      'image': _selectedImageBase64, // 空っぽの場合は空文字が入ります
                    });
                    _selectedImageBase64 = ''; // 次のために選択をリセット
                  });
                  _saveData();
                  _controller.clear();
                }
              },
              child: const Text('日時と写真をつけて追加'),
            ),
            const SizedBox(height: 20),

            // 履歴リスト表示
            Expanded(
              child: ListView.builder(
                itemCount: _memoList.length,
                itemBuilder: (context, index) {
                  final String? imageStr = _memoList[index]['image'];
                  
                  return Card(
                    color: Colors.grey,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      // 💡 【新機能】メモの左端（leading）に写真のサムネイルを配置します
                      leading: imageStr != null && imageStr.isNotEmpty
                          ? GestureDetector(
                              onPressed: () => _showLargeImage(imageStr), // 💡 タップで拡大
                              child: Container(
                                width: 50,
                                height: 50,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
                                child: Image.memory(base64Decode(imageStr), fit: BoxFit.cover),
                              ),
                            )
                          : const Icon(Icons.note, size: 40, color: Colors.white), // 写真がない場合はノートのアイコン
                      
                      title: Text(_memoList[index]['text'] ?? '', style: const TextStyle(fontSize: 18)),
                      subtitle: Text(_memoList[index]['date'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() => _memoList.removeAt(index));
                          _saveData();
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