# SharedPreferences wywołuje ten most przez JNI, poza grafem wywołań R8.
# Zachowaj nazwy i sygnatury metod suspend (w tym Continuation), aby release
# nie kończył odczytu ustawień błędem NoSuchMethodError dla getAll.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }

# package:jni wyszukuje te typy i pola po nazwie w lib/src/kotlin.dart.
# Samo zachowanie pluginu nie chroni refleksyjnych odwołań z Darta.
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsJvmKt { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
