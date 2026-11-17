# Huawei Push (huawei_push / HMS Core SDK). Flutter adds this file to the
# release build's R8 rules automatically.
#
# Keep rules from Huawei's Push Kit integration guide ("Configuring
# Obfuscation Scripts"): the SDK finds these classes by reflection.
-keep class com.huawei.hianalytics.** { *; }
-keep class com.huawei.updatesdk.** { *; }
-keep class com.huawei.hms.** { *; }

# Referenced by the SDK but not shipped in it: they exist only in Huawei's
# phone firmware or in optional Huawei SDKs, and the SDK checks for them
# before use.
-dontwarn com.huawei.android.os.BuildEx$VERSION
-dontwarn com.huawei.hianalytics.**
-dontwarn com.huawei.libcore.io.**
-dontwarn com.huawei.hms.availableupdate.UpdateAdapterMgr
