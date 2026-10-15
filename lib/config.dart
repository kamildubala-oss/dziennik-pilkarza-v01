/// Konfiguracja aplikacji.
///
/// Backend jest WBUDOWANY w aplikację (patrz `api.dart` i `local_db.dart`):
/// dane zapisują się na telefonie, nie trzeba uruchamiać żadnego serwera
/// ani podawać żadnych adresów. Aplikacja działa od razu po instalacji.
///
/// Funkcje AI trenera (czat, plan tygodnia, analiza słabych punktów) mają
/// tryb offline, który działa bez żadnej konfiguracji. Jeśli chcesz
/// odpowiedzi modelu językowego, podaj własny klucz API w ustawieniach
/// (Google Gemini, natywne API `generateContent`).
class AppConfig {
  AppConfig._();

  /// Adres bazowy API Gemini.
  static const String llmBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  /// Nazwa modelu.
  static const String llmModel = 'gemini-flash-latest';

  /// Szybszy model: używany do planu tygodnia i jako zapasowy, gdy główny
  /// jest przeciążony lub nie odpowiada.
  static const String llmFastModel = 'gemini-2.5-flash-lite';


  static const String coachSessionId = 'coach-default-session';
}
