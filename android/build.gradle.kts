allprojects {
    repositories {
        // Stub for play-services-tapandpay which is not publicly available.
        // Required transitively by stripe-android-issuing-push-provisioning (flutter_stripe).
        // Farlo does not use Stripe Issuing; this stub satisfies the build graph only.
        maven { url = uri("${rootProject.projectDir}/local-maven") }
        google()
        mavenCentral()
        // Required by flutter_stripe for stripe-android-issuing-push-provisioning.
        maven { url = uri("https://a.stripe-cloud.com/stripe-issuing-android") }
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
}

// Force all plugin subprojects to compile against SDK 36 so older plugins
// (e.g. add_2_calendar) don't fail when their transitive deps require SDK 34+.
// Skip :app — it's already evaluated via evaluationDependsOn above.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
                ?.compileSdk = 36
        }
    }

}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
