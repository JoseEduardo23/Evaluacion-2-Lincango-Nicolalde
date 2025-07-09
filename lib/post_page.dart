import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});
  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  
  final _tituloCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  double? lat, lon;

  // Images (web ↔ mobile)
  final List<Uint8List> _webImages = [];  
  final List<io.File>  _mobileImages = []; 
  static const int _maxPhotos = 5;
  static const int _maxSizeBytes = 2 * 1024 * 1024; // 2 MB

  bool loading = false;

  
  Future<void> _getLocation() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado')),
      );
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() { lat = pos.latitude; lon = pos.longitude; });
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    if ((_webImages.length + _mobileImages.length) >= _maxPhotos) return;

    final XFile? picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null) return;

    //web
    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > _maxSizeBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagen > 2 MB – elige otra.')),
        );
        return;
      }
      setState(() => _webImages.add(bytes));
      return;
    }

    //móvil
    final file = io.File(picked.path);
    final size = await file.length();
    if (size > _maxSizeBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen > 2 MB – elige otra.')),
      );
      return;
    }
    setState(() => _mobileImages.add(file));
  }

  Future<void> _submit() async {
    final titulo = _tituloCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final user = supabase.auth.currentUser;
    final totalImgs = _webImages.length + _mobileImages.length;

    if (titulo.isEmpty || lat == null || lon == null || totalImgs == 0 || user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Completa todo el formulario.')));
      return;
    }

    setState(() => loading = true);
    final postId = _uuid.v4();

    try {
      //Insertar post
      await supabase.from('posts').insert({
        'id': postId,
        'user_id': user.id,
        'titulo': titulo,
        'descripcion': desc,
        'lat': lat,
        'lon': lon,
      });

      //Cargar fotos y URLs
      Future<void> uploadBytes(Uint8List bytes, int idx) async {
        final filename = '${_uuid.v4()}.jpg';
        final path = 'sitios/$postId/$filename';
        await supabase.storage.from('sitios').uploadBinary(path, bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
        final url = supabase.storage.from('sitios').getPublicUrl(path);
        await supabase.from('photos').insert({'post_id': postId, 'url': url});
      }

      //web
      for (int i = 0; i < _webImages.length; i++) {
        await uploadBytes(_webImages[i], i);
      }
      //móvil
      for (int i = 0; i < _mobileImages.length; i++) {
        final bytes = await _mobileImages[i].readAsBytes();
        await uploadBytes(bytes, i);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sitio publicado exitosamente')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  void _mostrarFuenteImagen(){
    showModalBottomSheet(context: context, builder: (_){
      return SafeArea(child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar foto'),
            onTap: () async {
              Navigator.pop(context);
              final hasPermission = await _checkCameraPermission();
              if (hasPermission){
                _pickImage(fromCamera: true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permiso de cámara denegado')),
                );
              }
              
            },
          ),
          ListTile(leading: const Icon(Icons.photo),
          title: const Text('Elegir de galería'),
          onTap:(){
            Navigator.pop(context);
            _pickImage(fromCamera: false);
          },
          ),
        ],
      ),
      );
    },
    );
  }

  
  
  @override
  Widget build(BuildContext context) {
    final allImgs = [..._mobileImages.map((f) => f.path), ..._webImages];

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva publicación')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _tituloCtrl,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: Icon(lat == null ? Icons.location_on : Icons.check),
                    label: Text(lat == null ? 'Obtener ubicación' : 'Ubicación lista'),
                    onPressed: _getLocation,
                  ),
                  const SizedBox(height: 12),

                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // imágenes web
                      ..._webImages.map((bytes) => Image.memory(bytes, width: 80, height: 80, fit: BoxFit.cover)),
                      // imágenes mobile
                      ..._mobileImages.map((f) => Image.file(f, width: 80, height: 80, fit: BoxFit.cover)),
                      if (allImgs.length < _maxPhotos)
                        GestureDetector(
                          onTap: ()=> _mostrarFuenteImagen(),
                          child: Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[300],
                            child: const Icon(Icons.add_a_photo),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Publicar sitio'),
                  ),
                ],
              ),
            ),
    );
  }
}
