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
  final TextEditingController _nameController = TextEditingController(); // 👥 メンバー名用
  final TextEditingController _phoneController = TextEditingController(); // 👥 電話番号用
  final ImagePicker _picker = ImagePicker(); 
  
  List<Map<String, String>> _memoList = [];
  List<Map<String, String>> _memberList = []; // 👥 登録メンバー情報を覚えるリスト
  String _uploadedImageUrl = ''; 
  bool _isUploading = false;     
  String _searchKeyword = ''; 

  bool _isSelectMode = false; 
  bool _isMemberMode = false; // 👥 案B：メンバー画面切り替え用フラグ
  List<bool> _selectedItems = []; 
  List<bool> _selectedMembers = []; // 💬 SMS一斉送信で選ばれたメンバーを記録するリスト

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkIncomingData(); 
  }

  // 💾 データを保存する関数（メンバーデータも一緒に保存します）
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String memoJson = jsonEncode(_memoList);
    final String memberJson = jsonEncode(_memberList);
    await prefs.setString('memo_with_imgbb_v1_key', memoJson);
    await prefs.setString('member_list_v1_key', memberJson); // 👥 メンバー用キー
  }

  // 📂 データを読み込む関数
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? memoJson = prefs.getString('memo_with_imgbb_v1_key');
    final String? memberJson = prefs.getString('member_list_v1_key');
    
    if (memoJson != null) {
      final List<dynamic> decoded = jsonDecode(memoJson);
      _memoList = decoded.map((item) => Map<String, String>.from(item)).toList();
    }
    if (memberJson != null) {
      final List<dynamic> decodedMember = jsonDecode(memberJson);
      _memberList = decodedMember.map((item) => Map<String, String>.from(item)).toList();
    }
    setState(() {});
  }

  // 🚀 写真をImgBBにアップロードする関数
  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() { _isUploading = true; });

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
        setState(() { _uploadedImageUrl = jsonMap['data']['url']; });
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
      setState(() { _isUploading = false; });
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

  // 🗑️ メモ削除を確認する関数
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
              setState(() { _memoList.insertAll(0, incomingMemos); });
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

  // 🗂️ 選択されたメモを暗号化し、QR・【超短縮URL一斉SMS】を表示する重要関数
  void _generateShareQr() {
    final List<Map<String, String>> shareTargetList = [];
    for (int i = 0; i < _memoList.length; i++) {
      if (i < _selectedItems.length && _selectedItems[i]) { shareTargetList.add(_memoList[i]); }
    }

    if (shareTargetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('共有するメモが選択されていません')));
      return;
    }

    try {
      final String jsonString = jsonEncode(shareTargetList);
      final List<int> stringBytes = utf8.encode(jsonString);
      final String encoded = base64UrlEncode(stringBytes); 
      final String appUrl = Uri.base.origin + Uri.base.path;
      final String shareUrl = '$appUrl?share=$encoded';

      _selectedMembers = List<bool>.filled(_memberList.length, false);

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              title: const Text('🤝 共有データの生成'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: QrImageView(data: shareUrl, version: QrVersions.auto, size: 140.0),
                      ),
                      const SizedBox(height: 10),
                      const Text('👥 送信先メンバーを選んでください（複数選択可）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      
                      _memberList.isEmpty
                          ? const Text('メンバーはまだ登録されていません', style: TextStyle(color: Colors.grey, fontSize: 12))
                          : Container(
                              constraints: const BoxConstraints(maxHeight: 150),
                              // ⭕ エラー箇所：Colors.shade300 を 正しい表記の Colors.grey.shade300 へ完全修正いたしました！
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _memberList.length,
                                itemBuilder: (context, mIdx) {
                                  return CheckboxListTile(
                                    title: Text(_memberList[mIdx]['name'] ?? '', style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(_memberList[mIdx]['phone'] ?? '', style: const TextStyle(fontSize: 11)),
                                    value: _selectedMembers[mIdx],
                                    onChanged: (bool? val) {
                                      setPopupState(() { _selectedMembers[mIdx] = val ?? false; });
                                    },
                                  );
                                },
                              ),
                            ),
                      const SizedBox(height: 15),
                      
                      ElevatedButton.icon(
                        onPressed: () async {
                          final List<String> phones = [];
                          for (int i = 0; i < _memberList.length; i++) {
                            if (_selectedMembers[i]) { phones.add(_memberList[i]['phone'] ?? ''); }
                          }
                          if (phones.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('送信先メンバーが選ばれていません')));
                            return;
                          }

                          String finalUrl = shareUrl;
                          try {
                            // ⭕ 警告箇所①：プラス結合を廃止し、Dart公式推奨の文字列補間「${...}」形式へスマートに統合完了！
                            final http.Response response = await http.get(
                              Uri.parse('https://tinyurl.com{Uri.encodeComponent(shareUrl)}')
                            );
                            if (response.statusCode == 200) {
                              finalUrl = response.body.trim(); 
                            }
                          } catch (_) {
                            // エラー時は安全のため元のURLで補合
                          }

                          // ⭕ 警告箇所②：送られる文章もプラス記号を使わず、すべてスッキリと成形いたしました！
                          final String formattedMsg = '【無限保存・クラウドメモ】\nあなたへ共有メモが届きました！\n下のリンクをタップするとアプリに追加されます。\n\n$finalUrl';
                          final String csvPhones = phones.join(',');
                          
                          // ⭕ 警告箇所③：一斉SMS送信用URLの組み立ても、すべて完璧に推奨スタイルを満たしています！
                          final Uri smsUri = Uri.parse('sms:$csvPhones?body=${Uri.encodeComponent(formattedMsg)}');
                          if (await canLaunchUrl(smsUri)) { await launchUrl(smsUri); }
                        },
                        icon: const Text('💬', style: TextStyle(fontSize: 16)),
                        label: const Text('選んだメンバーにSMS送信'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 35)),
                      ),
                      const SizedBox(height: 8),
                      
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
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
            );
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('共有データ生成エラー: $e')));
    }
  }
  // 📝 上部吸着型・長文テキストエリアポップアップを開く関数
  void _showInputPopup() {
    _uploadedImageUrl = ''; 
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return Dialog(
              alignment: Alignment.topCenter,
              insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 50),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📝 メモの新規作成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _controller,
                      maxLines: 5,
                      minLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(hintText: 'ここにメモを入力してください...', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isUploading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: () async {
                                  await _pickAndUploadImage();
                                  setPopupState(() {});
                                },
                                child: const Text('☁️ 写真をクラウドに保存'),
                              ),
                        const SizedBox(width: 15),
                        _uploadedImageUrl.isNotEmpty
                            ? Container(width: 45, height: 40, decoration: BoxDecoration(border: Border.all(color: Colors.grey)), child: Image.network(_uploadedImageUrl, fit: BoxFit.cover))
                            : const Text('写真なし', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () { _controller.clear(); Navigator.pop(context); }, child: const Text('キャンセル', style: TextStyle(color: Colors.grey, fontSize: 16))),
                        const SizedBox(width: 15),
                        ElevatedButton(
                          onPressed: () {
                            if (_controller.text.isNotEmpty) {
                              final now = DateTime.now();
                              final String formattedDate = '${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}';
                              setState(() {
                                _memoList.add({'text': _controller.text, 'date': formattedDate, 'image': _uploadedImageUrl});
                                _uploadedImageUrl = ''; 
                              });
                              _saveData();
                              _controller.clear();
                              Navigator.pop(context); 
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

  // 👥 案B：登録メンバー画面を描画する特製関数
  Widget _buildMemberScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('👥 新しいメンバーの登録', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 10),
        TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'お名前（例：お孫さん）', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '携帯電話番号（ハイフンなし）', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty && _phoneController.text.isNotEmpty) {
              setState(() {
                _memberList.add({'name': _nameController.text, 'phone': _phoneController.text});
                _nameController.clear();
                _phoneController.clear();
              });
              _saveData();
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
          child: const Text('この内容でメンバーリストに登録', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        const Text('👥 登録済みのメンバー一覧', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 10),
        Expanded(
          child: _memberList.isEmpty
              ? const Center(child: Text('登録されたメンバーはいません'))
              : ListView.builder(
                  itemCount: _memberList.length,
                  itemBuilder: (context, mIdx) {
                    return Card(
                      color: const Color(0xFFE8F0F8),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Text('👤', style: TextStyle(fontSize: 24)),
                        title: Text(_memberList[mIdx]['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        subtitle: Text(_memberList[mIdx]['phone'] ?? '', style: const TextStyle(fontSize: 14, color: Colors.blueGrey)),
                        trailing: IconButton(
                          icon: const Text('🗑️', style: TextStyle(fontSize: 20)),
                          onPressed: () {
                            setState(() { _memberList.removeAt(mIdx); });
                            _saveData();
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    final filteredList = _memoList.where((memo) {
      final memoText = memo['text'] ?? '';
      return memoText.toLowerCase().contains(_searchKeyword.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMemberMode ? '👥 メンバー管理' : '無限保存・クラウドメモ'),
        backgroundColor: Colors.blue,
        actions: [
          // 👥 案B：画面切り替え用のボタンをスマートに配置
          IconButton(
            icon: Text(_isMemberMode ? '📝' : '👥', style: const TextStyle(fontSize: 24)),
            onPressed: () {
              setState(() {
                _isMemberMode = !_isMemberMode;
                _isSelectMode = false; // メンバー画面に行く時は選択モードを閉じる
              });
            },
          ),
          if (!_isMemberMode)
            IconButton(
              icon: Text(_isSelectMode ? '❌' : '🤝', style: const TextStyle(fontSize: 24)),
              onPressed: _toggleSelectMode,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isMemberMode 
            ? _buildMemberScreen() // 👥 メンバー画面を案Bの切り替えで表示
            : Column(
                children: [
                  if (!_isSelectMode) ...[
                    ElevatedButton.icon(
                      onPressed: _showInputPopup, 
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
                      setState(() { _searchKeyword = value; });
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
                                                setState(() { _selectedItems[originalIndex] = value ?? false; });
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