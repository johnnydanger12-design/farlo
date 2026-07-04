import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_message.dart';
import '../repositories/messaging_repository.dart';

class BookingChatScreen extends ConsumerStatefulWidget {
  const BookingChatScreen({
    super.key,
    required this.bookingId,
    required this.title,
    required this.subtitle,
  });

  /// Shown in the AppBar as the thread title (truck name or contact name).
  final String title;

  /// Optional subtitle line (event type · date).
  final String subtitle;

  final String bookingId;

  @override
  ConsumerState<BookingChatScreen> createState() => _BookingChatScreenState();
}

class _BookingChatScreenState extends ConsumerState<BookingChatScreen> {
  final _repo = MessagingRepository(Supabase.instance.client);
  final _messages = <BookingMessage>[];
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(authProvider).asData?.value?.id;
    final msgs = await _repo.fetchMessages(widget.bookingId);
    if (userId != null) await _repo.markAsRead(widget.bookingId, userId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(msgs);
      _loading = false;
    });
    _scrollToBottom();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('booking-chat-${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord;
            if (record.isEmpty) return;
            final msg = BookingMessage.fromMap(record);
            // Deduplicate: realtime fires for messages we just sent too.
            if (_messages.any((m) => m.id == msg.id)) return;
            setState(() => _messages.add(msg));
            _scrollToBottom();
            // Mark as read whenever a message arrives while the chat is open.
            final uid = ref.read(authProvider).asData?.value?.id;
            if (uid != null) _repo.markAsRead(widget.bookingId, uid);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    final userId = ref.read(authProvider).asData?.value?.id;
    if (userId == null) return;

    setState(() => _sending = true);

    try {
      await _repo.sendMessage(
        bookingId: widget.bookingId,
        senderId: userId,
        body: text,
      );
      // Realtime will deliver the message and deduplicate.
      // Only clear the input once the send is actually confirmed — clearing
      // it beforehand meant a failed send silently discarded the user's
      // typed message with no error shown and no way to recover the text.
      _textController.clear();
    } catch (e) {
      if (mounted) context.showError('Message not sent: ${sanitizeErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: AppTextStyles.heading3),
            Text(widget.subtitle, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        titleSpacing: 0,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                : _messages.isEmpty
                    ? _EmptyState(name: widget.title)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md + bottomInset,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final isMine = msg.senderId == userId;
                          final showDate = i == 0 ||
                              !_sameDay(_messages[i - 1].createdAt, msg.createdAt);
                          return Column(
                            children: [
                              if (showDate) _DateDivider(date: msg.createdAt),
                              _MessageBubble(message: msg, isMine: isMine),
                            ],
                          );
                        },
                      ),
          ),
          _InputBar(
            controller: _textController,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text('Start the conversation', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              'Send a message to $name about your event.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Date divider ─────────────────────────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday ? 'Today' : '${_months[date.month - 1]} ${date.day}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
          ),
          const Expanded(child: Divider(color: AppColors.divider)),
        ],
      ),
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});
  final BookingMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final timeStr = _fmtTime(message.createdAt.toLocal());

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
              ),
              child: Text(
                message.body,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isMine ? Colors.white : AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeStr,
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm + bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodySmall,
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(sending: sending, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onTap});
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Send message',
      button: true,
      child: GestureDetector(
        onTap: sending ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: sending
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
