plugins {
    id("com.android.application")
}

val cafeinaArm64Only = providers.gradleProperty("cafeinaArm64Only").orNull == "true"
val cafeinaAbis = if (cafeinaArm64Only) listOf("arm64-v8a")
    else listOf("arm64-v8a", "x86_64")

android {
    namespace = "com.cafeina.executor"
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "com.cafeina.executor"
        minSdk = 26
        targetSdk = 35
        versionCode = 10
        versionName = "0.10.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Also filter JNI libraries brought by the Godot AAR, not only CMake outputs.
        ndk {
            abiFilters += cafeinaAbis
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf("-DANDROID_STL=c++_shared")
                abiFilters += cafeinaAbis
            }
        }
    }

    sourceSets {
        getByName("main") {
            java.srcDir("../../executor-runtime/android")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../executor-runtime/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Luau JNI and the Godot AAR both use the shared C++ runtime.
    packaging {
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
        }
    }
}


dependencies {
    implementation("org.godotengine:godot:4.7.0.stable")
    // GodotActivity extends FragmentActivity; the Godot AAR marks this as runtime-only.
    implementation("androidx.fragment:fragment:1.8.6")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
