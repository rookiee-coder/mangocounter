import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/scan_chat_context.dart';
import '../domain/chat_message.dart';
import '../application/chat_controller.dart';
import 'widgets/botanical_markdown_text.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ScanChatContext? scanContext;
  final String? initialQuestion;

  const ChatScreen({
    super.key,
    this.scanContext,
    this.initialQuestion,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isContextExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider.notifier).initSession(
            scanContext: widget.scanContext,
            initialQuestion: widget.initialQuestion,
          );
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    ref.read(chatControllerProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _handlePromptTap(String prompt) {
    ref.read(chatControllerProvider.notifier).sendMessage(prompt);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final background = isDark ? AppColors.darkCanopy : AppColors.canvasCream;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    // Auto-scroll when messages change or loading state toggles
    ref.listen(chatControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length || prev?.isLoading != next.isLoading) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology_alt_rounded, color: primary, size: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI Agronomist',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: text,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'MANGO HARVEST ADVISOR',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Clear & Restart Chat',
            onPressed: () {
              ref.read(chatControllerProvider.notifier).clearChat();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat session restarted ✨'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'What I Can Help With',
            onPressed: () => _showCapabilitiesDialog(context, primary, text, surface),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Attached Scan Context Banner
            if (widget.scanContext != null)
              _buildScanContextBanner(
                context: context,
                ctx: widget.scanContext!,
                isDark: isDark,
                primary: primary,
                amber: amber,
                text: text,
                surface: surface,
                muted: muted,
              ),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == chatState.messages.length && chatState.isLoading) {
                    return _buildTypingIndicator(primary, surface, muted, isDark);
                  }

                  final msg = chatState.messages[index];
                  return _buildMessageItem(
                    message: msg,
                    primary: primary,
                    amber: amber,
                    surface: surface,
                    text: text,
                    muted: muted,
                    isDark: isDark,
                  );
                },
              ),
            ),

            // Quick Follow-up Suggestions Chips Bar
            if (chatState.suggestedPrompts.isNotEmpty && !chatState.isLoading)
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: chatState.suggestedPrompts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final suggestion = chatState.suggestedPrompts[index];
                    return ActionChip(
                      avatar: Icon(Icons.auto_awesome, size: 13, color: primary),
                      label: Text(
                        suggestion,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: text,
                        ),
                      ),
                      backgroundColor: surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: primary.withOpacity(0.35)),
                      ),
                      onPressed: () => _handlePromptTap(suggestion),
                    );
                  },
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14241B) : const Color(0xFFF3FAF5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: primary.withOpacity(0.25),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _textCtrl,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        keyboardType: TextInputType.text,
                        style: TextStyle(fontSize: 13.5, color: text),
                        decoration: InputDecoration(
                          hintText: 'Ask about harvest timing, fruit health, pests...',
                          hintStyle: TextStyle(fontSize: 12.5, color: muted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppColors.sunsetGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8A3D).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      tooltip: 'Send Message',
                      onPressed: chatState.isLoading ? null : _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanContextBanner({
    required BuildContext context,
    required ScanChatContext ctx,
    required bool isDark,
    required Color primary,
    required Color amber,
    required Color text,
    required Color surface,
    required Color muted,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isContextExpanded = !_isContextExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (ctx.imageBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        ctx.imageBytes!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.grass, color: primary, size: 20),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'TREE SCAN ATTACHED',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: primary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${ctx.totalCount} Mangoes',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Ripe: ${ctx.ripeCount}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: amber)),
                            const SizedBox(width: 8),
                            Text('Unripe: ${ctx.unripeCount}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.unripeGreen)),
                            if (ctx.overRipeCount > 0) ...[
                              const SizedBox(width: 8),
                              Text('Over: ${ctx.overRipeCount}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.overRipeEarth)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isContextExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (_isContextExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your harvest assistant can see this tree photo and will give you advice on when to pick and fruit care.',
                    style: TextStyle(fontSize: 11.5, color: muted, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Sensitivity: ${(ctx.confThreshold * 100).toStringAsFixed(0)}% · Speed: ${ctx.inferenceMs}ms',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: muted),
                      ),
                      if (ctx.aiVerifiedCount > 0) ...[
                        const Spacer(),
                        Text(
                          '✨ ${ctx.aiVerifiedCount} Checked',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageItem({
    required ChatMessage message,
    required Color primary,
    required Color amber,
    required Color surface,
    required Color text,
    required Color muted,
    required bool isDark,
  }) {
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant message bubble
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, right: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.eco_rounded, size: 16, color: primary),
          ),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: message.isError
                      ? Colors.red.withOpacity(0.3)
                      : primary.withOpacity(0.18),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'AI AGRONOMIST',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Copy advice',
                        color: muted,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied advice to clipboard 📋'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  BotanicalMarkdownText(
                    text: message.text,
                    primaryColor: primary,
                    baseStyle: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(Color primary, Color surface, Color muted, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.eco_rounded, size: 16, color: primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                ),
                const SizedBox(width: 10),
                Text(
                  'Preparing harvest advice...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCapabilitiesDialog(BuildContext context, Color primary, Color text, Color surface) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.psychology_alt_rounded, color: primary, size: 24),
            const SizedBox(width: 10),
            Text('How Your Assistant Can Help', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: text)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCapabilityItem(Icons.calendar_month_outlined, 'Harvest Timing', 'Estimates best picking dates and sweetness windows for your fruit harvest.'),
            _buildCapabilityItem(Icons.bug_report_outlined, 'Pest & Fruit Care', 'Provides solutions for fruit flies, spots, tree health, and fruit protection.'),
            _buildCapabilityItem(Icons.water_drop_outlined, 'Water & Plant Food', 'Recommends watering schedules and nutrition for sweeter, healthier fruits.'),
            _buildCapabilityItem(Icons.camera_alt_outlined, 'Tree Photo Analysis', 'Inspects your tree photo to give specific advice for your orchard.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('GOT IT')),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1F5D3F)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                Text(desc, style: const TextStyle(fontSize: 11.5, color: AppColors.mutedGraphite, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
