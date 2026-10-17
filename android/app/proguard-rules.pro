# SharedPreferences wywołuje ten most przez JNI, poza grafem wywołań R8.
# Zachowaj nazwy i sygnatury metod suspend (w tym Continuation), aby release
# nie kończył odczytu ustawień błędem NoSuchMethodError dla getAll.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }
