plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "kr.bangbang.geulgeul"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // **출시하면 영원히 바꿀 수 없다.** OAuth 콘솔 등록도 이 값에 묶인다.
        // 2026-08-21 에 `kr.bangbang.mapscratch` 에서 바꿨다 — mapscratch 는 개발
        // 초기 프로젝트명이고 제품명은 방방긁긁이다 (S3 N3).
        applicationId = "kr.bangbang.geulgeul"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // **아직 debug 키로 서명한다.** 출시에는 못 쓴다.
            //
            // Play App Signing 을 쓰기로 했다(2026-08-21) — Google 이 서명키를
            // 관리해 키를 잃을 위험이 없다. 다만 **최종 인증서 지문은 Play 에 한
            // 번 올려야 나오므로**, 그때까지는 debug 지문으로 OAuth 콘솔에 등록해
            // 개발한다. 출시 전에 **Play 앱 서명 키 지문을 추가 등록**해야 한다 —
            // 안 하면 스토어 버전에서만 로그인이 깨진다
            // (`source/backend/SYNC_CONTRACT.md` 11절 체크리스트).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
