import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostDetailPage extends StatefulWidget {
  final String postId;
  const PostDetailPage({super.key, required this.postId});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? post;
  List<dynamic> reviews = [];
  bool loading = true;

  String? currentUserId;
  late String currentRole; // visitante | publicador
  bool get isOwner => post?['user_id'] == currentUserId;

  final reviewController = TextEditingController();
  final Map<String, TextEditingController> responseCtrls = {};

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      Navigator.pop(context);
      return;
    }
    currentUserId ??= user.id;

    //Obtener rol del usuario
    final profile = await supabase
        .from('usuarios')
        .select('rol')
        .eq('id', currentUserId!)
        .single();
    currentRole = profile['rol'];

    print('Fotos: ${post?['photos']}');

    //Obtener post + fotos + autor
    post = await supabase
        .from('posts')
        .select('*, usuarios(username)')
        .eq('id', widget.postId)
        .single();

    print('Buscando fotos para post: ${widget.postId}');
    final fotos = await supabase
        .from('photos')
        .select('url')
        .eq('post_id', widget.postId);

    print('Fotos encontradas: $fotos');
    post!['photos'] = fotos;

    //Obtener reseñas con respuestas y autor de cada una
    reviews = await supabase
        .from('reviews')
        .select('*, usuarios(username), respuestas(*, usuarios(username))')
        .eq('post_id', widget.postId)
        .order('created_at', ascending: false);

    print('Cantidad de fotos que se mostrarán: ${post?['photos']?.length}');

    setState(() => loading = false);
  }

  Future<void> _addReview() async {
    final text = reviewController.text.trim();
    if (text.isEmpty) return;
    print('user_id reseña:$currentUserId');
    try {
      await supabase
          .from('reviews')
          .insert({
            'post_id': widget.postId,
            'user_id': currentUserId!,
            'contenido': text,
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Insert time out');
            },
          );
      reviewController.clear();
      await _initScreen(); // refrescar
    } catch (e) {
      print('Error al insertar reseña: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al insertar reseña')));
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    try {
      if (mounted) setState(() => loading = true);

      // 1. Eliminar respuestas relacionadas
      await supabase.from('respuestas').delete().eq('review_id', reviewId);

      // 2. Eliminar la reseña
      final result = await supabase
          .from('reviews')
          .delete()
          .eq('id', reviewId)
          .select() // ✅ obligatorio para usar maybeSingle
          .maybeSingle();

      debugPrint('Resultado de eliminación: $result');

      if (mounted) {
        setState(() {
          reviews.removeWhere((review) => review['id'] == reviewId);
        });
      }

      // 3. Recargar datos
      await _initScreen();
    } catch (e) {
      debugPrint('Error al eliminar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _removeReviewLocally(String reviewId) {
    if (!mounted) return;

    setState(() {
      reviews = reviews.where((r) => r['id'] != reviewId).toList();
    });
  }

  Future<void> _editReview(String reviewId, String currentContent) async {
    final textController = TextEditingController(text: currentContent);
    if (reviewId.isEmpty) return;

    final newContent = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar reseña'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Edita tu reseña',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newContent != null && newContent.isNotEmpty) {
      try {
        final result = await supabase
            .from('reviews')
            .update({'contenido': newContent})
            .eq('id', reviewId)
            .select()
            .maybeSingle();

        if (result == null) {
          debugPrint('No se encontró la reseña para editar.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La reseña no fue encontrada.')),
            );
          }
          return;
        }

        debugPrint('Reseña actualizada: $result');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Reseña actualizada')));
          await _initScreen();
        }
      } catch (e) {
        debugPrint('Error al editar reseña: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al editar: ${e.toString()}')),
          );
        }
      }
    }
  }

  // Método para eliminar una respuesta
  Future<void> _deleteResponse(String responseId) async {
    try {
      // Verificar si la respuesta existe
      final exists = await supabase
          .from('respuestas')
          .select()
          .eq('id', responseId)
          .maybeSingle();

      if (exists == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La respuesta no existe')),
          );
        }
        return;
      }

      // Verificar permisos
      final isAuthor = exists['user_id'] == currentUserId;
      final isPostOwner = isOwner;

      if (!isAuthor && !isPostOwner) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No tienes permisos')));
        }
        return;
      }

      // Eliminar
      await supabase
          .from('respuestas')
          .delete()
          .eq('id', responseId)
          .select()
          .single();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Respuesta eliminada')));
        await _initScreen();
      }
    } catch (e) {
      debugPrint('Error eliminando respuesta: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Future<void> _addResponse(String reviewId) async {
    final ctrl = responseCtrls[reviewId];
    if (ctrl == null) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    await supabase.from('respuestas').insert({
      'review_id': reviewId,
      'user_id': currentUserId,
      'respuesta': text,
    });
    ctrl.clear();
    await _initScreen();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final fotos = (post?['photos'] as List<dynamic>)
        .map((e) => e['url'] as String)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(post?['titulo'] ?? 'Detalle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Galería (se mantiene igual)
            SizedBox(
              height: 220,
              child: PageView.builder(
                itemCount: fotos.length,
                controller: PageController(viewportFraction: 0.9),
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        fotos[index],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.error),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            // Descripción
            Text(
              post?['descripcion'] ?? '',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            // Autor
            Text(
              'Publicado por: ${post?['usuarios']['username']}',
              style: const TextStyle(color: Colors.grey),
            ),
            const Divider(height: 32),

            // Lista de reseñas - Aquí están los principales cambios
            const Text(
              'Reseñas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ...reviews.map((rev) {
              final reviewId = rev['id'] as String;
              responseCtrls.putIfAbsent(
                reviewId,
                () => TextEditingController(),
              );

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encabezado de reseña con botones de editar/eliminar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            rev['usuarios']['username'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          // Botones solo para el autor de la reseña
                          if (rev['user_id'] == currentUserId)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () =>
                                      _editReview(rev['id'], rev['contenido']),
                                  padding: EdgeInsets.zero,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteReview(rev['id']),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                        ],
                      ),

                      const SizedBox(height: 4),
                      Text(rev['contenido']),
                      const SizedBox(height: 8),

                      // Lista de respuestas
                      ...(rev['respuestas'] as List<dynamic>).map(
                        (resp) => Padding(
                          padding: const EdgeInsets.only(left: 12, top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.reply,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Encabezado de respuesta con botones
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${resp['usuarios']['username']}: ',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                        // Botones para autor o dueño del post
                                        if (resp['user_id'] == currentUserId ||
                                            isOwner)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              size: 16,
                                            ),
                                            onPressed: () =>
                                                _deleteResponse(resp['id']),
                                            padding: EdgeInsets.zero,
                                          ),
                                      ],
                                    ),
                                    Text(
                                      resp['respuesta'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Formulario de respuesta (dueño del post o autor de reseña)
                      if ((isOwner && currentRole == 'publicador') ||
                          rev['user_id'] == currentUserId)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: responseCtrls[reviewId],
                                  decoration: const InputDecoration(
                                    hintText: 'Responder...',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, size: 20),
                                onPressed: () => _addResponse(reviewId),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),

            // Formulario para nueva reseña (se mantiene igual)
            const SizedBox(height: 12),
            TextField(
              controller: reviewController,
              decoration: const InputDecoration(
                labelText: 'Escribe una reseña',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _addReview,
                child: const Text('Publicar reseña'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
