import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_page.dart';
import 'post_page.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;
  String? username;
  String? rol;
  int currentPage = 0;
  final int postsPerPage = 8;
  String searchQuery = '';
  bool hasMorePosts = true;
  bool loadingProfile = true;
  bool loadingPosts = true;
  List<dynamic> posts = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<dynamic> reviews = [];
  bool loadingReviews = false;

  Future<void> fetchReviews() async {
    setState(() => loadingReviews = true);

    try {
      final data = await supabase
          .from('respuestas')
          .select('*'); // Aquí ajusta el select según tus columnas y relaciones

      setState(() {
        reviews = data;
        loadingReviews = false;
      });
    } catch (e) {
      setState(() => loadingReviews = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar respuestas: ${e.toString()}'),
          ),
        );
      }
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      // Soft delete (marcar como eliminado)
      await supabase
          .from('posts')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', postId);

      if (mounted) {
        setState(() {
          posts.removeWhere((post) => post['id'] == postId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post eliminado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadAll() async {
    await fetchUserProfile();
    if (rol != null) {
      await fetchPosts();
    }
  }

  Future<void> fetchUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
      );
      return;
    }

    final response = await supabase
        .from('usuarios')
        .select()
        .eq('id', user.id)
        .single();
    if (response == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error al obtener perfil.')));
      return;
    }

    setState(() {
      username = response['username'];
      rol = response['rol'];
      loadingProfile = false;
    });
  }

  Future<void> _initScreen() async {
  setState(() {
    loadingPosts = true; // o loadingReviews, si estás trabajando con reseñas
  });

  await fetchUserProfile(); // si quieres refrescar datos del usuario
  await fetchPosts();       // o fetchReviews() si estás mostrando reseñas

  setState(() {
    loadingPosts = false;
  });
}

  Future<void> fetchPosts() async {
    try {
      setState(() => loadingPosts = true);
      final userId = supabase.auth.currentUser?.id;

      final data = await supabase
          .from('posts')
          .select(
            'id, titulo, created_at,lat, lon, usuarios(username), photos(url)',
          )
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: false);

      if (mounted) {
        // Verificar favoritos para cada post
        final postsWithFavorites = await Future.wait(
          data.map((post) async {
            final isFavorite = await _isFavorite(post['id']);
            return {...post, 'is_favorite': isFavorite};
          }),
        );

        setState(() {
          posts = postsWithFavorites;
          loadingPosts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loadingPosts = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar posts: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _openMap(double lat, double lon) async {
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );

    final Uri appleMapsUrl = Uri.parse('https://maps.apple.com/?q=$lat,$lon');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl);
      } else {
        throw 'No se pudo abrir ninguna aplicación de mapas';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al abrir el mapa: $e')));
      }
    }
  }

 Future<void> _deleteResponse(String responseId) async {
  try {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) throw Exception('Usuario no autenticado');

    // Consultar la respuesta con su review y post relacionados
    final responseData = await supabase
        .from('respuestas')
        .select('id, user_id, review_id, review_id!inner(post_id), review_id!inner(posts!inner(user_id))')
        .eq('id', responseId)
        .maybeSingle();

    if (responseData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La respuesta no existe')),
        );
      }
      return;
    }

    final isAuthor = responseData['user_id'] == currentUserId;
    final postOwnerId = responseData['review_id']['posts']['user_id'];
    final isPostOwner = postOwnerId == currentUserId;

    if (!isAuthor && !isPostOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tienes permiso para eliminar esta respuesta')),
        );
      }
      return;
    }

    // Eliminar (ya validado el permiso)
    await supabase.from('respuestas').delete().eq('id', responseId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respuesta eliminada correctamente')),
      );
      await _initScreen();
    }
  } catch (e) {
    debugPrint('Error eliminando respuesta: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
}

  Future<bool> _isFavorite(String postId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await supabase
        .from('favoritos')
        .select()
        .eq('user_id', userId)
        .eq('post_id', postId)
        .maybeSingle();

    return response != null;
  }

  Future<void> _toggleFavorite(dynamic post) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final postId = post['id'];
      if (userId == null || postId == null) return;

      final isFav = await _isFavorite(postId);

      if (isFav) {
        await supabase
            .from('favoritos')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
      } else {
        await supabase.from('favoritos').insert({
          'user_id': userId,
          'post_id': postId,
        });
      }

      if (mounted) {
        setState(() {
          post['is_favorite'] = !isFav;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en favoritos: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  Future<void> _showDeleteDialog(String postId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: const Text(
            '¿Estás seguro de que quieres eliminar esta publicación?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePost(postId);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublisher = rol == 'publicador';
    final isVisitor = rol == 'visitante';

    final filteredPosts = posts.where((post) {
      final titulo = (post['titulo']?.toString().toLowerCase() ?? '');
      return titulo.contains(searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: loadingProfile
            ? const Text('Cargando…')
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar posts...',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          setState(() => searchQuery = value.toLowerCase());
                        },
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                    if (searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () => setState(() => searchQuery = ''),
                      ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),

      body: loadingProfile || loadingPosts
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchPosts,
              child: filteredPosts.isEmpty
                  ? Center(
                      child: Text(
                        isPublisher
                            ? 'Aún no has publicado sitios.'
                            : 'No hay publicaciones disponibles.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: filteredPosts.length,
                      itemBuilder: (context, index) {
                        final post = filteredPosts[index];
                        final fotos = (post['photos'] ?? []) as List;
                        final firstPhoto =
                            fotos.isNotEmpty && fotos[0]?['url'] != null
                            ? fotos[0]['url'] as String
                            : null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: firstPhoto != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      firstPhoto,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image),
                                    ),
                                  )
                                : const Icon(Icons.image, size: 40),
                            title: Text(post['titulo'] ?? 'Sin título'),
                            subtitle: Text(
                              'Autor: ${post['usuarios']?['username'] ?? 'Desconocido'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (post['lat'] != null && post['lon'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 4,
                                    ), // Espaciado opcional
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.map,
                                        color: Colors.blue,
                                      ),
                                      iconSize: 22,
                                      onPressed: () =>
                                          _openMap(post['lat'], post['lon']),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),

                                // Botón de eliminar (solo publishers)
                                if (isPublisher) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _showDeleteDialog(post['id']),
                                    padding: EdgeInsets.zero,
                                  ),
                                  const SizedBox(width: 4),
                                ],

                                // Botón de favoritos (solo visitantes)
                                if (isVisitor)
                                  IconButton(
                                    icon: Icon(
                                      post['is_favorite'] == true
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _toggleFavorite(post),
                                    padding: EdgeInsets.zero,
                                  ),

                                // Ícono de flecha (siempre visible)
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right, size: 20),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PostDetailPage(postId: post['id']),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

      floatingActionButton: isPublisher
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreatePostPage()),
                );
                setState(() => loadingPosts = true);
                await fetchPosts();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva publicación'),
            )
          : null,
    );
  }
}
