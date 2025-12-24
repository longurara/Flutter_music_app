import com.android.build.gradle.BaseExtension
import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android")
        if (androidExt is LibraryExtension) {
            if (androidExt.namespace == null && project.name == "flutter_media_metadata") {
                androidExt.namespace = "com.alexmercerind.flutter_media_metadata"
            }
            androidExt.compileSdk = 34
        } else {
            val baseExt =
                extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            baseExt?.compileSdkVersion(34)
            if (project.name == "flutter_media_metadata") {
                try {
                    baseExt?.javaClass?.getMethod("setNamespace", String::class.java)
                        ?.invoke(baseExt, "com.alexmercerind.flutter_media_metadata")
                } catch (_: Exception) {
                    // ignore; namespace not supported on this AGP
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
