import org.gradle.api.tasks.bundling.Jar
import org.gradle.api.tasks.JavaExec
import org.gradle.api.tasks.scala.ScalaCompile
import org.gradle.external.javadoc.StandardJavadocDocletOptions
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

plugins {
    `java-library`
    `maven-publish`
    scala
    kotlin("jvm") version "2.4.10"
}

group = "io.vinarytree"
version = "4.0.0-rc.6"

java {
    toolchain.languageVersion = JavaLanguageVersion.of(
        providers.gradleProperty("javaToolchain").orElse("22").get().toInt()
    )
    withSourcesJar()
    withJavadocJar()
}

repositories {
    mavenCentral()
}

scala {
    scalaVersion = "3.8.4"
}

dependencies {
    testImplementation(kotlin("stdlib"))
    testImplementation("org.scala-lang:scala3-library_3:3.8.4")
    testImplementation("org.clojure:clojure:1.12.5")
    testImplementation(platform("org.junit:junit-bom:6.1.2"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

sourceSets {
    named("test") {
        resources.srcDir("src/test/clojure")
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 22
    options.encoding = "UTF-8"
}

tasks.withType<KotlinJvmCompile>().configureEach {
    compilerOptions.jvmTarget = JvmTarget.JVM_22
}

tasks.withType<ScalaCompile>().configureEach {
    scalaCompileOptions.additionalParameters = listOf("-release:22")
}

tasks.test {
    useJUnitPlatform()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    systemProperty("java.io.tmpdir", layout.buildDirectory.dir("tmp").get().asFile)
}

tasks.withType<Javadoc>().configureEach {
    (options as StandardJavadocDocletOptions)
        .addStringOption("Xdoclint:all,-missing", "-quiet")
    (options as StandardJavadocDocletOptions).addBooleanOption("Werror", true)
}

tasks.named<Jar>("sourcesJar") {
    include("**/*.java")
    includeEmptyDirs = false
}

tasks.named<Jar>("jar") {
    manifest.attributes["Automatic-Module-Name"] = "io.vinarytree.interop"
}

val providerSmoke = tasks.register<JavaExec>("providerSmoke") {
    group = "verification"
    description = "Exercises every JVM host-provider ABI through native downcalls and upcalls."
    dependsOn(tasks.named("testClasses"))
    classpath = sourceSets["test"].runtimeClasspath
    mainClass = "io.vinarytree.interop.ProviderAbiSmoke"
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    systemProperty("java.io.tmpdir", layout.buildDirectory.dir("tmp").get().asFile)
}

fun registerLanguageProviderSmoke(taskName: String, entryPoint: String) =
    tasks.register<JavaExec>(taskName) {
        group = "verification"
        description = "Proves that $entryPoint can implement and export every JVM provider family."
        dependsOn(tasks.named("testClasses"))
        classpath = sourceSets["test"].runtimeClasspath
        mainClass = entryPoint
        jvmArgs("--enable-native-access=ALL-UNNAMED")
        systemProperty("java.io.tmpdir", layout.buildDirectory.dir("tmp").get().asFile)
    }

val kotlinProviderSmoke =
    registerLanguageProviderSmoke("kotlinProviderSmoke", "io.vinarytree.interop.KotlinProviderSmoke")
val scalaProviderSmoke =
    registerLanguageProviderSmoke("scalaProviderSmoke", "io.vinarytree.interop.ScalaProviderSmoke")
val clojureProviderSmoke =
    tasks.register<JavaExec>("clojureProviderSmoke") {
        group = "verification"
        description = "Proves that Clojure can implement and export every JVM provider family."
        dependsOn(tasks.named("testClasses"))
        classpath = sourceSets["test"].runtimeClasspath
        mainClass = "clojure.main"
        args("-m", "io.vinarytree.interop.provider-smoke")
        jvmArgs("--enable-native-access=ALL-UNNAMED")
        systemProperty("java.io.tmpdir", layout.buildDirectory.dir("tmp").get().asFile)
    }

tasks.named("check") {
    dependsOn(providerSmoke, kotlinProviderSmoke, scalaProviderSmoke, clojureProviderSmoke)
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            artifactId = "vinary-tree-interop"
            from(components["java"])
            pom {
                name = "vinary-tree interop ABI"
                description = "A stable, dependency-free resource ABI for sharing live dictionaries, weighted automata, and host-defined algebra safely across Vinary Tree libraries and languages."
                url = "https://github.com/vinary-tree/vinary-tree-interop"
                licenses {
                    license {
                        name = "Apache License 2.0"
                        url = "https://www.apache.org/licenses/LICENSE-2.0.txt"
                    }
                }
                developers {
                    developer {
                        id = "dylon"
                        name = "Dylon Edwards"
                        email = "dylon.devo@gmail.com"
                    }
                }
                scm {
                    connection = "scm:git:https://github.com/vinary-tree/vinary-tree-interop.git"
                    developerConnection = "scm:git:ssh://git@github.com/vinary-tree/vinary-tree-interop.git"
                    url = "https://github.com/vinary-tree/vinary-tree-interop"
                }
            }
        }
    }
    repositories {
        maven {
            name = "staging"
            url = uri(
                providers.gradleProperty("stagingRepository")
                    .orElse(layout.buildDirectory.dir("staging-deploy").map { it.asFile.absolutePath })
                    .get()
            )
        }
    }
}
