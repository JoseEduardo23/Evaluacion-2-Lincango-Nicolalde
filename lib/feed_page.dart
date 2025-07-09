import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detail_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final supabase = Supabase.instance.client;
  List<dynamic> posts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final response = await supabase
        .from('posts')
        .select('id, titulo, descripcion, photos(url)')
        .order('created_at', ascending: false);

    setState(() {
      posts = response;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Lugares turísticos')),
      body: ListView.builder(
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final imgUrl = (post['photos'] as List).isNotEmpty
              ? post['photos'][0]['url']
              : null;

          return ListTile(
            leading: imgUrl != null
                ? Image.network(imgUrl, width: 60, height: 60, fit: BoxFit.cover)
                : const Icon(Icons.image_not_supported),
            title: Text(post['titulo'] ?? 'Sin título'),
            subtitle: Text(post['descripcion'] ?? ''),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailPage(postId: post['id']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
