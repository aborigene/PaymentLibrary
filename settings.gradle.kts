//=============================================================================
// settings.gradle.kts
//
// Este arquivo de configuração do projeto define os módulos a serem incluídos.
//=============================================================================
import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
        maven { url = uri("https://www.jitpack.io") } // Add this line
    }
    // A declaração de plugins aqui garante que o Gradle possa encontrar os plugins Android
    plugins {
        id("com.android.application") version "8.11.1"
        id("com.android.library") version "8.11.1"
        id("org.jetbrains.kotlin.android") version "2.2.0"
        id("com.github.kezong.fat-aar") version "1.3.8"
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "PaymentLibrary"
include(":app")
include(":PaymentLibrary")