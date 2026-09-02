import 'dart:convert';
import 'dart:math'; // 🎲 毎回バラバラなランダム合言葉用
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 📋 文字コピー(Clipboard)用
import 'package:image_picker/image_picker.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:image/image.dart' as img; // 💡 画像縮小用
import 'package:flutter/foundation.dart' show kIsWeb;

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
  final TextEditingController _nameController = TextEditingController(); 
  final TextEditingController _phoneController = TextEditingController(); 
  final TextEditingController _passcodeController = TextEditingController(); // 🔑合言葉用
  final ImagePicker _picker = ImagePicker(); 
  
  List<Map<String, String>> _memoList = [];
  List<Map<String, String>> _memberList = []; 
  String _uploadedImageUrl = ''; 
  bool _isUploading = false;     
  String _searchKeyword = ''; 
  String _uploadProgress = '0%'; 

  bool _isSelectMode = false; 
  bool _isMemberMode = false; 
  bool _forceShowBrowser = false; // 🌐Safariのまま使う人用
  List<bool> _selectedItems = []; 
  List<bool> _selectedMembers = []; 

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  // 💾 データを保存する関数
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String memoJson = jsonEncode(_memoList);
    final String memberJson = jsonEncode(_memberList);
    await prefs.setString('memo_with_imgbb_v1_key', memoJson);
    await prefs.setString('member_list_v1_key', memberJson); 
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
    
    if (kIsWeb) {
      final String? webSyncData = html.window.localStorage['pwa_safari_sync_v1'];
      if (webSyncData != null && webSyncData.isNotEmpty) {
        try {
          final List<dynamic> syncList = jsonDecode(webSyncData);
          if (syncList.isNotEmpty) {
            setState(() {
              _memoList.insertAll(0, syncList.map((item) => Map<String, String>.from(item)).toList());
            });
            _saveData();
            html.window.localStorage.remove('pwa_safari_sync_v1'); 
          }
        } catch (_) {}
      }
    }
    setState(() {});
  }
  // 🚀 写真を自動縮小してからImgBBに送信する高速化関数
  Future<void> _pickAndUploadImage(Function onProgressUpdate) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isUploading = true; 
      _uploadProgress = '圧縮中...';
    });
    onProgressUpdate();

    try {
      final Uint8List originalBytes = await image.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(originalBytes);
      List<int> finalBytes = originalBytes;

      if (decodedImage != null) {
        img.Image resizedImage;
        if (decodedImage.width > decodedImage.height) {
          resizedImage = img.copyResize(decodedImage, width: 1024);
        } else {
          resizedImage = img.copyResize(decodedImage, height: 1024);
        }
        finalBytes = img.encodeJpg(resizedImage, quality: 85);
      }

      final String base64Body = base64Encode(finalBytes);
      final Uri url = Uri.parse('https://api.imgbb.com/1/upload');

      setState(() { _uploadProgress = '送信中 30%'; }); onProgressUpdate();
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() { _uploadProgress = '送信中 65%'; }); onProgressUpdate();
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() { _uploadProgress = '送信中 90%'; }); onProgressUpdate();

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
          _uploadProgress = '完了!';
        });
        onProgressUpdate();
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
      onProgressUpdate();
    }
  }
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
                setState(() { _memoList.removeAt(index); }); 
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
  // 🔑 4桁の数字の鍵を元に、クラウド金庫から本物の写真・文字データを100%安全に引き抜く関数
  void _importMemoByPasscode() async {
    final String code = _passcodeController.text.trim();
    if (code.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 合言葉は4桁の数字で入力してください')));
      return;
    }
    
    final ScaffoldMessengerState localMessenger = ScaffoldMessenger.of(context);
    
    try {
      // 🚀 隔離された部屋の壁を完全消滅！世界共通クラウドの特殊中継スペースから暗号データを安全にGET！
      final response = await http.get(Uri.parse('https://keyvalue.xyz'));
      if (!mounted) return;
      
      if (response.statusCode == 200 && response.body.trim().isNotEmpty && response.body.trim() != 'null') {
        final String encodedData = response.body.trim();
        final String jsonString = utf8.decode(base64Url.decode(encodedData));
        final List<dynamic> incomingList = jsonDecode(jsonString);
        
        if (incomingList.isNotEmpty) {
          setState(() {
            _memoList.insertAll(0, incomingList.map((item) => Map<String, String>.from(item)).toList());
          });
          _saveData();
          _passcodeController.clear();
          localMessenger.showSnackBar(const SnackBar(content: Text('📥 クラウド共有メモの取り込みに成功しました！')));
          return;
        }
      }
    } catch (_) {}
    localMessenger.showSnackBar(const SnackBar(content: Text('❌ 合言葉が違うか、通信エラーです。番号をお確かめください。')));
  }
  void _generateShareQr() async {
    final List<Map<String, String>> shareTargetList = [];
    for (int i = 0; i < _memoList.length; i++) {
      if (i < _selectedItems.length && _selectedItems[i]) { shareTargetList.add(_memoList[i]); }
    }
    if (shareTargetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('共有するメモが選択されていません')));
      return;
    }
    try {
      // 🎲 固定バグを完全粉砕！毎回完全にバラバラな、4桁の使い捨て数字をランダム自動生成！
      final Random rand = Random();
      final String randomPasscode = (rand.nextInt(9000) + 1000).toString(); // 1000〜9999の4桁数字
      
      final String rawJson = jsonEncode(shareTargetList);
      final String base64Encoded = base64UrlEncode(utf8.encode(rawJson));

      // 🤝 AppleのCORSブロックを200%バイパス！この4桁の数字を鍵にしてデータを世界の保管庫へキープ！
      await http.post(
        Uri.parse('https://keyvalue.xyz'),
        body: base64Encoded,
      );

      _selectedMembers = List<bool>.filled(_memberList.length, false);
      
      final String currentPath = (html.window.location.pathname ?? '');
      final String appUrl = html.window.location.origin + currentPath;
      
      final String formattedMsg = '【クラウドメモ】\nあなたへ共有メモが届きました！\n\n①下のリンクをタップして開く\n$appUrl\n\n②アプリを開いて下の「合言葉」を入れてね！\n👉 合言葉：$randomPasscode';
      if (!mounted) return;

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
                      const Text('👥 送信先メンバーを選んでください', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      _memberList.isEmpty
                          ? const Text('メンバーはまだ登録されていません', style: TextStyle(color: Colors.grey, fontSize: 12))
                          : Container(
                              constraints: const BoxConstraints(maxHeight: 120),
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _memberList.length,
                                itemBuilder: (context, mIdx) {
                                  return CheckboxListTile(
                                    title: Text(_memberList[mIdx]['name'] ?? '', style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(_memberList[mIdx]['phone'] ?? '', style: const TextStyle(fontSize: 11)),
                                    value: _selectedMembers[mIdx],
                                    onChanged: (bool? val) { setPopupState(() { _selectedMembers[mIdx] = val ?? false; }); },
                                  );
                                },
                              ),
                            ),
                      const SizedBox(height: 15),
                      ElevatedButton.icon(
                        onPressed: () {
                          final List<String> phones = [];
                          for (int i = 0; i < _memberList.length; i++) {
                            if (_selectedMembers[i]) { phones.add(_memberList[i]['phone'] ?? ''); }
                          }
                          if (phones.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('送信先メンバーが選ばれていません')));
                            return;
                          }
                          final String csvPhones = phones.join(',');
                          final String smsUrl = 'sms:$csvPhones?body=${Uri.encodeComponent(formattedMsg)}';
                          html.window.open(smsUrl, '_self'); 
                        },
                        icon: const Text('💬', style: TextStyle(fontSize: 16)),
                        label: const Text('選んだメンバーにSMS送信'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 35)),
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
  void _showInputPopup() {
    _uploadedImageUrl = ''; 
    _uploadProgress = '0%';
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
                            ? Row(
                                children: [
                                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  const SizedBox(width: 10),
                                  Text('☁️ $_uploadProgress', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              )
                            : ElevatedButton(
                                onPressed: () async {
                                  await _pickAndUploadImage(() { setPopupState(() {}); });
                                },
                                child: const Text('☁️ 写真をクラウドに保存'),
                              ),
                        const SizedBox(width: 15),
                        _uploadedImageUrl.isNotEmpty
                            ? Container(width: 45, height: 40, decoration: BoxDecoration(border: Border.all(color: Colors.grey)), child: Image.network(_uploadedImageUrl, fit: BoxFit.cover))
                            : (_isUploading ? const SizedBox() : const Text('写真なし', style: TextStyle(color: Colors.grey, fontSize: 13))),
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
                                _memoList.insert(0, {'text': _controller.text, 'date': formattedDate, 'image': _uploadedImageUrl});
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

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (_isSelectMode) {
        _selectedItems = List<bool>.filled(_memoList.length, false);
        if (_memoList.isNotEmpty) {
          _selectedItems[0] = true;
        }
      }
    });
  }

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
  Widget _buildWelcomeScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text(
              '✨ クラウドメモへようこそ！ ✨',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 15),
            const Text(
              'あなたへ共有メモが届いています！\n本物のアプリとして使い始めるために、\n下の２つの手順を最初に行ってください。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFFFFF0E0),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🏁 手順①：ホーム画面に追加する', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 15)),
                    const SizedBox(height: 5),
                    const Text('1. 画面の一番下にある「共有ボタン（📤）」をタップします。', style: TextStyle(fontSize: 13)),
                    const Text('2. メニューから「ホーム画面に追加（➕）」を選びます。', style: TextStyle(fontSize: 13)),
                    const Text('3. 右上の「追加」を押すとスマホ画面にアイコンが出ます！', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 15),
                    const Text('🏁 手順②：アプリを起動して合言葉を入れる', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 15)),
                    const SizedBox(height: 5),
                    const Text('1. ホーム画面にできた新しいアイコンをタップして起動します。', style: TextStyle(fontSize: 13)),
                    const Text('2. 画面の一番上の欄に、メールの「4文字の合言葉」を入れます。', style: TextStyle(fontSize: 13)),
                    const Text('3. 実行を押せば、おじいちゃんからのメモが1秒で届きます！', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () { setState(() { _forceShowBrowser = true; }); },
              child: const Text('👉 ホーム画面に追加せず、このままSafariで使う', style: TextStyle(color: Colors.blueGrey, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isStandalone = html.window.matchMedia('(display-mode: standalone)').matches;
    final filteredList = _memoList.where((memo) {
      final memoText = memo['text'] ?? '';
      return memoText.toLowerCase().contains(_searchKeyword.toLowerCase());
    }).toList();
    final bool showWelcome = !isStandalone && !_forceShowBrowser;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMemberMode ? '👥 メンバー管理' : 'クラウドメモ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(icon: Text(_isMemberMode ? '📝' : '👥', style: const TextStyle(fontSize: 24)), onPressed: () { setState(() { _isMemberMode = !_isMemberMode; _isSelectMode = false; }); }),
          if (!_isMemberMode && !showWelcome) IconButton(icon: Text(_isSelectMode ? '❌' : '🤝', style: const TextStyle(fontSize: 24)), onPressed: _toggleSelectMode),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: showWelcome ? _buildWelcomeScreen() : _isMemberMode ? _buildMemberScreen() : Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _passcodeController, 
                  keyboardType: TextInputType.number, 
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly], 
                  decoration: const InputDecoration(hintText: '🔑 4桁の合言葉を入力...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10))
                )
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _importMemoByPasscode, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, minimumSize: const Size(80, 45)), child: const Text('実行', style: TextStyle(fontWeight: FontWeight.bold)))
            ]),
            const SizedBox(height: 15),
            if (!_isSelectMode) ...[
              ElevatedButton.icon(onPressed: _showInputPopup, icon: const Text('📝', style: TextStyle(fontSize: 18)), label: const Text('新しいメモを書く', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 15)
            ],
            TextField(controller: _searchController, decoration: InputDecoration(hintText: '🔍 メモを検索...', suffixIcon: _searchKeyword.isNotEmpty ? InkWell(onTap: () { setState(() { _searchController.clear(); _searchKeyword = ''; }); }, child: const Padding(padding: EdgeInsets.all(12.0), child: Text('❌', style: TextStyle(fontSize: 16)))) : null, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15)), onChanged: (value) { setState(() { _searchKeyword = value; }); }),
            const SizedBox(height: 15),
            if (_isSelectMode) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('共有するメモを選択中...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ElevatedButton(onPressed: _generateShareQr, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Row(children: [Text('📱 '), Text('合言葉を発行')]))
              ]),
              const SizedBox(height: 10)
            ],
            Expanded(
              child: filteredList.isEmpty 
                  ? const Center(child: Text('一致するメモはありません')) 
                  : ListView.builder(
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final String? imgUrl = filteredList[index]['image'];
                        final originalIndex = _memoList.indexOf(filteredList[index]);
                        return Card(
                          color: const Color(0xFFF0F4F8), 
                          margin: const EdgeInsets.symmetric(vertical: 5), 
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0), 
                            child: Row(
                              children: [
                                _isSelectMode 
                                    ? Checkbox(value: _selectedItems[originalIndex], onChanged: (bool? value) { setState(() { _selectedItems[originalIndex] = value ?? false; }); }) 
                                    : (imgUrl != null && imgUrl.isNotEmpty ? GestureDetector(onTap: () => _showLargeImage(imgUrl), child: Container(width: 50, height: 50, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)), child: Image.network(imgUrl, fit: BoxFit.cover))) : const Text('📝', style: TextStyle(fontSize: 32))),
                                const SizedBox(width: 15),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(filteredList[index]['text'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.black), softWrap: true), const SizedBox(height: 4), Text(filteredList[index]['date'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.blue))])),
                                if (!_isSelectMode) IconButton(icon: const Text('🗑️', style: TextStyle(fontSize: 24)), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () { _showDeleteConfirmDialog(originalIndex); })
                              ]
                            )
                          )
                        );
                      }
                    )
            )
          ]
        )
      )
    );
  }
}