import 'dart:convert';
// 👇 1つ目のエラー（Uint8List）を直すために、この一業を一番上に追加しました！
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

  // ==========================================
  // 🔑 【最重要】ここにあなたのCloudinaryの情報を貼り付けてください
  // ==========================================
  final String cloudName = 'ijl7laxp';
  final String uploadPreset = 'hexdmmxx';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 💾 データを保存する関数
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_memoList);
    await prefs.setString('memo_with_cloudinary_v1_key', jsonString);
  }

  // 📂 データを読み込む関数
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('memo_with_cloudinary_v1_key');
    if (jsonString != null) {
      setState(() {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _memoList = decoded.map((item) => Map<String, String>.from(item)).toList();
      });
    }
  }

  // 🚀 【完全Web対応版】写真をインターネット倉庫にアップロードする関数
  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isUploading = true; 
    });

    try {
      // 💡 2つ目のエラー（non-nullable）対策：型に「?」をつけず「Uint8List」として確実に読み込みます
      final Uint8List imageBytes = await image.readAsBytes();

      final url = Uri.parse('https://cloudinary.com');
      
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: image.name,
        ));

      final response = await request.send();

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = jsonDecode(responseString);

        setState(() {
          _uploadedImageUrl = jsonMap['secure_url'];
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('アップロードに失敗しました。設定を確認してください。')),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
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
                          color: Colors.grey,
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
                                : const Icon(Icons.note, size: 40, color: Colors.white), 
                            
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