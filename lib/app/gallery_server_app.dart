part of '../main.dart';

class GalleryServerApp extends StatelessWidget {
  const GalleryServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gallery Server MVP',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}
