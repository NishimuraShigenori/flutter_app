import 'dart:convert'; // 💡 複雑なデータを保存するために追加
import 'package:flutter/material.dart';
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
  
  // 💡 【重要】文字と日付をセット（Map型）にして保存するリストに変更します
  List<Map<String, String>> _memoList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 💾 データをスマホに保存する関数
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    // 複雑なリストを文字列（JSON）に変換して丸ごと保存します
    final String jsonString = jsonEncode(_memoList);
    await prefs.setString('memo_with_date_key', jsonString);
  }

  // 📂 スマホからデータを読み込む関数
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('memo_with_date_key');
    if (jsonString != null) {
      setState(() {
        // 保存された文字列を、元の「文字と日付のセットリスト」に復元します
        final List<dynamic> decoded = jsonDecode(jsonString);
        _memoList = decoded.map((item) => Map<String, String>.from(item)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日時も記録するメモアプリ'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _controller, 
              decoration: const InputDecoration(hintText: 'メモを入力して追加'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  // 💡 現在の「年/月/日 時:分」を綺麗に整えて取得します
                  final now = DateTime.now();
                  final String formattedDate = 
                      '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} '
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

                  setState(() {
                    // 💡 「text」と「date」をペアにしてリストに追加します
                    _memoList.add({
                      'text': _controller.text,
                      'date': formattedDate,
                    });
                  });
                  _saveData(); // 保存する
                  _controller.clear();
                }
              },
              child: const Text('日時をつけて追加'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _memoList.length,
                itemBuilder: (context, index) {
                  return Card(
                    color: const Color.fromARGB(255, 229, 228, 228), // 薄いグレーの枠
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      // 💡 メモの本編（文字）を表示
                      title: Text(
                        _memoList[index]['text'] ?? '',
                        style: const TextStyle(fontSize: 18),
                      ),
                      // 💡 【新機能】メモの下側に、小さめの文字で記録された日時を表示
                      subtitle: Text(
                        _memoList[index]['date'] ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() => _memoList.removeAt(index));
                          _saveData(); // 削除時も保存
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