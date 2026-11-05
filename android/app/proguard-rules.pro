# LocalDrop release shrinking rules.

# WorkManager (pulled in by the Google Mobile Ads SDK) is started at app
# launch and creates its Room database by reflection (WorkDatabase_Impl).
# Without these rules R8 renames/removes the generated class and the app
# crashes on startup with "Failed to create an instance of
# androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** extends androidx.room.RoomDatabase { *; }
# WorkManager also creates its input mergers by reflection, and its own rule
# keeps these classes without their constructors.
-keep class * extends androidx.work.InputMerger { <init>(); }

# Our own platform code: called from the manifest and by JNI from Rust.
-keep class app.localdrop.localdrop.HostingService { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
