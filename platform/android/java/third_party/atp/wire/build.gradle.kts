// :atp-wire, vendored from the ATP drop beside this file (../README.md); this build file is GDatp's own.
// Plain Kotlin/JVM: framing, the protocol's codecs and the caller checks the provider kit builds on.
plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    systemProperty("atp.fixtures", file("../fixtures").absolutePath)
}
