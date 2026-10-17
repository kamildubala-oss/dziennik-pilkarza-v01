# Runner jest tworzony przez Androida poza grafem wywołań aplikacji.
# Reguły dotyczą wyłącznie instrumentowanego wariantu startupSmoke.
-keep class androidx.test.** { *; }
-keep class org.junit.** { *; }
-keep class junit.** { *; }
-keep class dev.flutter.plugins.integration_test.** { *; }
