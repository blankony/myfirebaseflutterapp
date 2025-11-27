import 'dart:async';

// Tipe Event
enum AiEventType { newChat, loadChat }

// Kelas Event
class AiPageEvent {
  final AiEventType type;
  final String? sessionId;
  AiPageEvent({required this.type, this.sessionId});
}

// Event Bus Controller
class AiPageEventBus {
  final _controller = StreamController<AiPageEvent>.broadcast();
  
  Stream<AiPageEvent> get stream => _controller.stream;
  
  void fire(AiPageEvent event) {
    _controller.sink.add(event);
  }
  
  void dispose() {
    _controller.close();
  }
}

// Instance Global yang akan dipakai bersama
final aiPageEventBus = AiPageEventBus();