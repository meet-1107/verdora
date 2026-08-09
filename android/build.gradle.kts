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
    // Some plugins (e.g. flutter_plugin_android_lifecycle) require compileSdk
    // 36+. Force every plugin module to compile against 36. (The :app module
    // sets compileSdk 36 directly; skip it here so we never call afterEvaluate
    // on the already-evaluated app project.)
    if (project.name != "app") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android")
            if (androidExtension != null) {
                try {
                    androidExtension.javaClass
                        .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                        .invoke(androidExtension, 36)
                } catch (_: Exception) {
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
