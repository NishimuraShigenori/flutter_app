import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 📋 文字コピー(Clipboard)用
import 'package:image_picker/image_picker.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart'; 

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
  final TextEditingController _searchController = TextEditingController(); 
  final ImagePicker _picker = ImagePicker(); 
  
  List<Map<String, String>> _memoList = [];
  String _uploadedImageUrl = ''; 
  bool _isUploading = false;     
  String _searchKeyword = ''; 

  bool _isSelectMode = false; 
  List<bool> _selectedItems = []; 

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkIncomingData(); 
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

  // 🚀 写真をImgBBにアップロードする関数
  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isUploading = true; 
    });

    try {
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64Body = base64Encode(imageBytes);

      final Uri url = Uri.parse('https://api.imgbb.com/1/upload');
      
      final response = await http.post(
        url,
        body: {
          'key': 'f4b3e12ae146cf9e2c030c3d74e4a4d6', 
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
            title: const Text('アップロード失敗'),
            content: Text('コード: ${response.statusCode}\n\n${response.body}'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('通信エラー'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        ),
      );
    } finally {
      setState(() {
        _isUploading = false; 
      });
    }
  }
  // 🔍 写真を大きく表示する関数
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

  // 🗑️ 削除を確認する関数
  void _showDeleteConfirmDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('メモの削除確認'),
          content: const Text('このメモを本当に削除してもよろしいですか？\n削除したメモは元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('いいえ', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _memoList.removeAt(index)); 
                _saveData(); 
                Navigator.pop(context); 
              },
              child: const Text('はい', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  // 🔗 相手から渡された共有URLデータを安全に解読して取り込む関数
  void _checkIncomingData() {
    final Uri uri = Uri.base; 
    if (uri.queryParameters.containsKey('share')) {
      try {
        final String encodedData = uri.queryParameters['share']!;
        final String jsonString = utf8.decode(base64Url.decode(encodedData));
        final List<dynamic> incomingList = jsonDecode(jsonString);

        if (incomingList.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showReceiveDialog(incomingList.map((item) => Map<String, String>.from(item)).toList());
          });
        }
      } catch (e) {
        // 解析エラー時は何もしない
      }
    }
  }
  // 📥 共有メモの受信確認ポップアップ
  void _showReceiveDialog(List<Map<String, String>> incomingMemos) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📥 共有メモの受信'),
        content: Text('他の人から ${incomingMemos.length} 件のメモが届きました！\nあなたのメモ帳に追加しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              setState(() {
                _memoList.insertAll(0, incomingMemos);
              });
              _saveData();
              Navigator.pop(context);
              
              if (kIsWeb) {
                final String origin = html.window.location.origin.toString();
                final String path = html.window.location.pathname.toString();
                html.window.history.replaceState(null, '', origin + path);
              }
            },
            child: const Text('追加する', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🗂️ 選択されたメモをまとめてQR・SMS・コピー用URLにする関数
  void _generateShareQr() {
    final List<Map<String, String>> shareTargetList = [];
    for (int i = 0; i < _memoList.length; i++) {
      if (i < _selectedItems.length && _selectedItems[i]) {
        shareTargetList.add(_memoList[i]);
      }
    }

    if (shareTargetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('共有するメモが選択されていません')),
      );
      return;
    }

    try {
      final String jsonString = jsonEncode(shareTargetList);
      final List<int> stringBytes = utf8.encode(jsonString);
      final String encoded = base64UrlEncode(stringBytes); 

      final String appUrl = Uri.base.origin + Uri.base.path;
      final String shareUrl = '$appUrl?share=$encoded';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🤝 共有用データ生成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('近くの人にはQRコードを、\n遠くの人には下のボタンからSMSやコピーで送れます。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 15),
              SizedBox(
                width: 150,
                height: 150,
                child: QrImageView(data: shareUrl, version: QrVersions.auto, size: 150.0),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: () async {
                  final Uri smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(shareUrl)}');
                  if (await canLaunchUrl(smsUri)) { await launchUrl(smsUri); }
                },
                icon: const Text('💬', style: TextStyle(fontSize: 16)),
                label: const Text('ショートメールで送る'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 35)),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareUrl));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📋 共有リンクをコピーしました！')));
                },
                icon: const Text('📋', style: TextStyle(fontSize: 16)),
                label: const Text('リンクをコピー'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 35)),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('共有データ生成エラー: $e')));
    }
  }
  // 📝 案②：にしむら様設計の上部吸着型・長文テキストエリアポップアップを開く関数
  void _showInputPopup() {
    // ポップアップを開く前に、写真の一時保存データを綺麗にリセット
    _uploadedImageUrl = ''; 

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return Dialog(
              // ⭕ キーボード対策：ポップアップの位置を「画面の最上部(top)」にピタッと吸着させます！
              alignment: Alignment.topCenter,
              insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 50),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📝 メモの新規作成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    
                    // ⭕ 長文対応：最初から5行分の広い空間を確保し、はみ出しても自動で縦スクロールします！
                    TextField(
                      controller: _controller,
                      maxLines: 5,
                      minLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: 'ここにメモを入力してください...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 15),

                    // 📷 ポップアップ内でクラウド写真を安全に管理するエリア
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isUploading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: () async {
                                  // 親画面のアップロード関数を実行
                                  await _pickAndUploadImage();
                                  // アップロードが終わったらポップアップ内の画面表示を最新に更新
                                  setPopupState(() {});
                                },
                                child: const Text('☁️ 写真をクラウドに保存'),
                              ),
                        const SizedBox(width: 15),
                        _uploadedImageUrl.isNotEmpty
                            ? Container(
                                width: 45,
                                height: 40,
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                                child: Image.network(_uploadedImageUrl, fit: BoxFit.cover),
                              )
                            : const Text('写真なし', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // 🚪 下部のボタンエリア
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _controller.clear();
                            Navigator.pop(context);
                          },
                          child: const Text('キャンセル', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton(
                          onPressed: () {
                            if (_controller.text.isNotEmpty) {
                              final now = DateTime.now();
                              final String formattedDate = '${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}';
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
                              Navigator.pop(context); // 入力完了後にポップアップを閉じる
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                          child: const Text('追加する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🔘 選択モードをONにして、直近10件に自動チェックを入れる関数
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (_isSelectMode) {
        _selectedItems = List<bool>.filled(_memoList.length, false);
        final int startIndex = _memoList.length > 10 ? _memoList.length - 10 : 0;
        for (int i = startIndex; i < _memoList.length; i++) { _selectedItems[i] = true; }
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final filteredList = _memoList.where((memo) {
      final memoText = memo['text'] ?? '';
      return memoText.toLowerCase().contains(_searchKeyword.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('無限保存・クラウドメモ'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: Text(_isSelectMode ? '❌' : '🤝', style: const TextStyle(fontSize: 24)),
            onPressed: _toggleSelectMode,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // ⭕ 新しいレイアウト：トップページをスッキリさせ、お洒落な新規作成ボタンを配置！
            if (!_isSelectMode) ...[
              ElevatedButton.icon(
                onPressed: _showInputPopup, // 🚀 にしむら様設計の巨大ポップアップを起動
                icon: const Text('📝', style: TextStyle(fontSize: 18)),
                label: const Text('新しいメモを書く', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
            ],
            
            // 🔍 検索窓
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 メモを検索...',
                suffixIcon: _searchKeyword.isNotEmpty
                    ? InkWell(
                        onTap: () {
                          setState(() {
                            _searchController.clear();
                            _searchKeyword = '';
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: Text('❌', style: TextStyle(fontSize: 16)),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              ),
              onChanged: (value) {
                setState(() {
                  _searchKeyword = value;
                });
              },
            ),
            const SizedBox(height: 15),

            if (_isSelectMode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('共有するメモを選択中...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ElevatedButton(
                    onPressed: _generateShareQr,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('📱 ', style: TextStyle(fontSize: 16)),
                        Text('QRコードを生成'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            Expanded(
              child: filteredList.isEmpty
                  ? const Center(child: Text('一致するメモはありません'))
                  : ListView.builder(
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final String? imageUrlStr = filteredList[index]['image'];
                        final originalIndex = _memoList.indexOf(filteredList[index]);

                        if (_selectedItems.length != _memoList.length) {
                          _selectedItems = List<bool>.filled(_memoList.length, false);
                        }

                        return Card(
                          color: const Color(0xFFF0F4F8), 
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
                            child: Row(
                              children: [
                                _isSelectMode
                                    ? Checkbox(
                                        value: _selectedItems[originalIndex],
                                        onChanged: (bool? value) {
                                          setState(() {
                                            _selectedItems[originalIndex] = value ?? false;
                                          });
                                        },
                                      )
                                    : (imageUrlStr != null && imageUrlStr.isNotEmpty
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
                                        : const Text('📝', style: TextStyle(fontSize: 32))), 
                                const SizedBox(width: 15),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        filteredList[index]['text'] ?? '', 
                                        style: const TextStyle(fontSize: 16, color: Colors.black),
                                        softWrap: true,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        filteredList[index]['date'] ?? '', 
                                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                                      ),
                                    ],
                                  ),
                                ),

                                if (!_isSelectMode)
                                  IconButton(
                                    icon: const Text('🗑️', style: TextStyle(fontSize: 24)),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _showDeleteConfirmDialog(originalIndex); 
                                    },
                                  ),
                              ],
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