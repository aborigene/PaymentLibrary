# ==============================================================================
# PaymentLibrary ProGuard Rules - Obfuscate internals, keep public API
# ==============================================================================

# Keep public API classes and ALL their members (including nested classes)
-keep public class com.dynatracese.paymentlibrary.PaymentClient {
    public *;
}
-keep public class com.dynatracese.paymentlibrary.PaymentClient$** {
    *;
}

-keep public class com.dynatracese.paymentlibrary.BusinessEventsClient {
    public *;
}
-keep public class com.dynatracese.paymentlibrary.BusinessEventsClient$** {
    *;
}

-keep public class com.dynatracese.paymentlibrary.PaymentCrashHandler {
    public *;
}
-keep public class com.dynatracese.paymentlibrary.PaymentCrashHandler$** {
    *;
}

# Keep public interfaces and their methods
-keep public interface com.dynatracese.paymentlibrary.** {
    public *;
}

# Keep data classes used in public API (for serialization)
-keepclassmembers class * {
    public <init>(...);
}

# Keep Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Keep Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.dynatracese.paymentlibrary.**$$serializer { *; }
-keepclassmembers class com.dynatracese.paymentlibrary.** {
    *** Companion;
}

# Keep source file names and line numbers for crash reports
-keepattributes SourceFile,LineNumberTable

# Rename source file attribute to hide real file names
-renamesourcefileattribute SourceFile

# Enable aggressive obfuscation
-repackageclasses 'o'
-allowaccessmodification
-optimizationpasses 5
