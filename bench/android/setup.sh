#!/bin/bash
# Copies the Android demo to <dest> and sets it up for one tool, leaving Example/AndroidDemo as it is.
#
#   bench/android/setup.sh swiftshot|paparazzi|roborazzi <dest> [forks]
#
# swiftshot   the project as it is (swiftshot adds its Gradle task through an init script).
# paparazzi   app.cash.paparazzi plugin + ComposablePreviewScanner, a parameterized test over
#             BenchMatrix in <forks> shard classes; `:app:recordPaparazziDebug`.
# roborazzi   io.github.takahirom.roborazzi plugin with generateComposePreviewRobolectricTests and
#             a custom ComposePreviewTester over BenchMatrix, <forks> generated test classes;
#             `:app:recordRoborazziDebug`.
#
# Gradle's build cache is turned off in the copy, so no run is served from another run's (or
# another tool's) outputs: every compile in a cold run really compiles.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tool=$1 dest=$2 forks=${3:-1}
config=$here/bench.json
v() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versions"][sys.argv[2]])' "$config" "$1"; }

rm -rf "$dest"; mkdir -p "$dest"
(cd "$root/Example/AndroidDemo" && tar cf - --exclude=./build --exclude='./*/build' --exclude=./.gradle --exclude=./.kotlin --exclude=./local.properties .) | (cd "$dest" && tar xf -)
# The local SDK location (CI has ANDROID_HOME instead).
[ -f "$root/Example/AndroidDemo/local.properties" ] && cp "$root/Example/AndroidDemo/local.properties" "$dest/"
python3 - "$dest/gradle.properties" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(?m)^org\.gradle\.caching=.*$', 'org.gradle.caching=false', s)
if 'org.gradle.caching' not in s: s += '\norg.gradle.caching=false\n'
open(p, 'w').write(s)
PY

# Adds a plugin to :app's plugins block, imports at the top and a block at the end.
patch_app() {  # plugin-id version imports(newline separated) block
    python3 - "$dest/app/build.gradle.kts" "$1" "$2" "$3" "$4" <<'PY'
import sys
path, plugin, version, imports, block = sys.argv[1:6]
s = open(path).read()
s = s.replace("plugins {\n", 'plugins {\n    id("%s") version "%s"\n' % (plugin, version), 1)
if imports.strip(): s = imports.strip() + "\n\n" + s
s = s.rstrip() + "\n\n// --- swiftshot benchmark ---\n" + block.strip() + "\n"
open(path, 'w').write(s)
PY
}

test_dir=$dest/app/src/test/java/com/swiftshot/demo/bench
common_block() {  # extra test settings shared by both Gradle tools
    cat <<EOF
tasks.withType<Test>().configureEach {
    maxParallelForks = $forks
    maxHeapSize = "3g"
    for (key in listOf("bench.devices", "bench.languages", "bench.appearances", "bench.limit")) {
        findProperty(key)?.let { systemProperty(key, it.toString()) }
    }
}
EOF
}

case $tool in
swiftshot) ;;
paparazzi)
    mkdir -p "$test_dir"
    cp "$here/common/BenchMatrix.kt" "$here/paparazzi/PaparazziPreviewTests.kt" "$test_dir/"
    {
        echo "package com.swiftshot.demo.bench"
        echo
        echo "import org.junit.runner.RunWith"
        echo "import org.junit.runners.Parameterized"
        for ((i = 0; i < forks; i++)); do
            cat <<EOF

@RunWith(Parameterized::class)
class PaparazziPreviewTest$i(shot: Shot) : PaparazziPreviewTest(shot) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun values(): List<Shot> = BenchMatrix.shard($i, $forks)
    }
}
EOF
        done
    } > "$test_dir/PaparazziPreviewShards.kt"
    patch_app app.cash.paparazzi "$(v paparazzi)" "" "$(cat <<EOF
dependencies {
    testImplementation("io.github.sergio-sastre.ComposablePreviewScanner:android:$(v composable_preview_scanner)")
    testImplementation("junit:junit:$(v junit)")
}

$(common_block)
EOF
)"
    ;;
roborazzi)
    mkdir -p "$test_dir"
    cp "$here/common/BenchMatrix.kt" "$here/roborazzi/BenchComposePreviewTester.kt" "$test_dir/"
    patch_app io.github.takahirom.roborazzi "$(v roborazzi)" "import com.github.takahirom.roborazzi.ExperimentalRoborazziApi" "$(cat <<EOF
android {
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

roborazzi {
    @OptIn(ExperimentalRoborazziApi::class)
    generateComposePreviewRobolectricTests {
        enable = true
        packages = listOf("com.swiftshot.demo")
        testerQualifiedClassName = "com.swiftshot.demo.bench.BenchComposePreviewTester"
        robolectricConfig = mapOf("sdk" to "[$(v robolectric_sdk)]")
        generatedTestClassCount = $forks
    }
}

dependencies {
    testImplementation("io.github.takahirom.roborazzi:roborazzi:$(v roborazzi)")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:$(v roborazzi)")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose-preview-scanner-support:$(v roborazzi)")
    testImplementation("io.github.sergio-sastre.ComposablePreviewScanner:android:$(v composable_preview_scanner)")
    testImplementation("org.robolectric:robolectric:$(v robolectric)")
    testImplementation("junit:junit:$(v junit)")
    testImplementation(platform(libs.compose.bom))
    testImplementation("androidx.compose.ui:ui-test-junit4")
}

$(common_block)

tasks.withType<Test>().configureEach {
    // Recommended by Roborazzi for image fidelity.
    systemProperty("robolectric.pixelCopyRenderMode", "hardware")
    // The SDK 36 Robolectric sandbox reaches into FileDescriptor internals, which JDK 17+ hides.
    jvmArgs("--add-exports=java.base/jdk.internal.access=ALL-UNNAMED", "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED", "--add-opens=java.base/java.io=ALL-UNNAMED")
}
EOF
)"
    ;;
*) echo "usage: $0 swiftshot|paparazzi|roborazzi <dest> [forks]" >&2; exit 2 ;;
esac
echo "$tool project: $dest"
