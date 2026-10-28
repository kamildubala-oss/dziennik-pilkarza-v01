/// Zachowuje pytanie poprzedzające pierwszą z czterech ostatnich odpowiedzi.
/// Ogranicza wyłącznie widok, nie zapis ani kontekst rozmowy wysyłany do AI.
int visibleChatStart(List<String> roles, {int maxReplies = 4}) {
  assert(maxReplies > 0);
  final replies = [for (var i = 0; i < roles.length; i++) if (roles[i] == 'assistant') i];
  if (replies.length <= maxReplies) return 0;
  final first = replies[replies.length - maxReplies];
  return first > 0 && roles[first - 1] == 'user' ? first - 1 : first;
}
