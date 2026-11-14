// :atp-provider, ATP's provider kit, vendored from the ATP drop beside this file (../README.md); this build file is
// GDatp's own. The kit is GDatp's ATP provider: the Binder service, the consent screen, grants and channels.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.nujan_agent.atp.provider"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        aidl = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

// ATP's provider and host interfaces compile from the drop's aidl folder, so there is one copy of them to check.
androidComponents {
    onVariants { variant -> variant.sources.aidl?.addStaticSourceDirectory(file("../aidl").absolutePath) }
}

tasks.withType<Test>().configureEach {
    systemProperty("atp.fixtures", file("../fixtures").absolutePath)
}

dependencies {
    api(project(":atp-wire"))
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("junit:junit:4.13.2")
}
