# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in C:\src\flutter\packages\flutter_tools\gradle\proguard-android.txt
# and the Android SDK's default ProGuard settings.

# Keep classes used by Firebase
-keep class com.google.firebase.** { *; }

# Keep classes used by Flutter
-keep class io.flutter.** { *; }

# Suppress Play Core warnings (Deferred Components)
-dontwarn com.google.android.play.core.**
-dontnote com.google.android.play.core.**

# If the above doesn't work, we can also add the specific rules from missing_rules.txt
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Added rule for class repackaging optimization
-repackageclasses ''
