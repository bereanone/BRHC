import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/font_scale.dart';
import 'package:brhc_app/widgets/chapter_blocks_view.dart';

class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        toolbarHeight: 40,
        elevation: 0,
      ),
      body: const SafeArea(
        child: ChapterBlocksView(chapterId: 0),
      ),
    );
  }
}
