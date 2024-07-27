import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostsPage extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final String name;
  final String uid;
  final Function(List<Map<String, dynamic>>) onPostsUpdated;

  PostsPage({
    required this.posts,
    required this.initialIndex,
    required this.name,
    required this.uid,
    required this.onPostsUpdated,
  });

  @override
  _PostsPageState createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  late ScrollController _scrollController;
  final double _itemHeight = 600; // Default item height
  bool _isScrollInitialized = false;
  String? _postToDeleteId; // Track the postId for deletion
  String? _profileImageUrl; // To store the profile image URL

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _fetchProfileImageUrl();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isScrollInitialized) {
        _scrollToInitialIndex(widget.initialIndex);
        _isScrollInitialized = true;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _fetchProfileImageUrl() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
      final data = userDoc.data();
      setState(() {
        _profileImageUrl = data?['profileImageUrl'];
      });
    } catch (e) {
      print('Error fetching profile image URL: ${e.toString()}');
    }
  }

  void _scrollToInitialIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index >= 0 && index < widget.posts.length) {
        if (widget.posts.length == 1) {
          // Handle case with only one item
          print('Single item case, no scrolling needed.');
          return;
        }

        double scrollOffset = _itemHeight * index;

        // Ensure ScrollController is attached
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            scrollOffset,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ).then((_) {
            print('Scroll completed to item $index');
          }).catchError((error) {
            print('Error scrolling to item $index: $error');
          });
        } else {
          print('Scroll controller is not attached');
        }
      } else {
        print('Index $index is out of range');
      }
    });
  }

  Future<void> _deletePost(String postId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    try {
      final userPostRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('posts').doc(postId);
      final explorePostRef = FirebaseFirestore.instance.collection('explore_posts').doc(postId);

      await userPostRef.delete();
      print('Deleted from user post reference: ${userPostRef.path}');
      
      await explorePostRef.delete();
      print('Deleted from explore post reference: ${explorePostRef.path}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post deleted successfully')),
      );
    } catch (e) {
      print('Error deleting post: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting post: ${e.toString()}')),
      );
    }
  }

  void _showDeleteConfirmationDialog() async {
    if (_postToDeleteId == null) return;

    bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Delete'),
        content: Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePost(_postToDeleteId!);
      setState(() {
        _postToDeleteId = null; // Clear the postId after deletion
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          if (_postToDeleteId != null) // Show delete button if postId is set
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _showDeleteConfirmationDialog,
            ),
        ],
        backgroundColor: Color.fromARGB(255, 53, 48, 115), // AppBar background color
        iconTheme: IconThemeData(color: Colors.white), // Set icon color to white
      ),
      backgroundColor: Color.fromARGB(255, 53, 48, 115), // Background color of the Scaffold
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .collection('posts')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.white)));
          } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No posts found', style: TextStyle(color: Colors.white)));
          } else {
            final posts = snapshot.data!.docs.map((doc) {
              var data = doc.data() as Map<String, dynamic>;
              return {
                'postId': doc.id,
                'title': data['title'] ?? '',
                'description': data['description'] ?? '',
                'imageUrl': data['imageUrl'] ?? '',
              };
            }).toList();

            widget.onPostsUpdated(posts);

            return ListView.builder(
              controller: _scrollController,
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final postId = post['postId'] ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPostHeader(postId),
                      SizedBox(height: 4.0),
                      AspectRatio(
                        aspectRatio: 1.0,
                        child: GestureDetector(
                          onTap: () {
                            print('Tapped on image $index');
                            _scrollToInitialIndex(index);
                          },
                          child: CachedNetworkImage(
                            imageUrl: post['imageUrl'] ?? '',
                            fit: BoxFit.cover,
                            placeholder: (context, url) => CircularProgressIndicator(),
                            errorWidget: (context, url, error) => Icon(Icons.error),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                        child: Text(
                          post['title'] ?? '',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                        child: Text(post['description'] ?? '', style: TextStyle(color: Colors.white)),
                      ),
                      SizedBox(height: 8.0),
                    ],
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }

  Widget _buildPostHeader(String postId) {
    return Container(
      color: Color.fromARGB(255, 40, 35, 88), // Darker purple for the post header
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: _profileImageUrl != null
                    ? CachedNetworkImageProvider(_profileImageUrl!)
                    : AssetImage('assets/default_profile.png') as ImageProvider, // Default image if URL is null
                backgroundColor: Colors.transparent, // Ensure profile images are visible
              ),
              SizedBox(width: 8),
              Text(
                widget.name,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white), // Ensure text is visible
              ),
            ],
          ),
        ],
      ),
    );
  }
}
