plugins {
    id("com.android.application")
}

android {
    namespace = "com.cafeina.executor"
    compileSdk = 35
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "com.cafeina.executor"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.2.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf("-DANDROID_STL=c++_shared")
                abiFilters += listOf("arm64-v8a", "x86_64")
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
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
