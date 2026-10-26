# Builds the macOS CLI and the iOS-simulator agent dylib into ./bin
PREFIX ?= /usr/local
SIM_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
AGENT_SRC := Agent/Agent.swift Agent/WatchAgent.swift Agent/Common.swift Agent/Discovery.swift Shared/JobModel.swift
WATCH_SDK := $(shell xcrun --sdk watchsimulator --show-sdk-path)
BUILD := .build/agent

all: bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib bin/SwiftshotNoBoot.dylib bin/SwiftshotNoBoot-watchOS.dylib bin/swiftshot-simhost

bin/swiftshot: Package.swift $(wildcard Sources/swiftshot/*.swift) Shared/JobModel.swift
	swift build -c release --product swiftshot
	mkdir -p bin && rm -f bin/swiftshot && cp .build/release/swiftshot bin/swiftshot

bin/SwiftshotAgent.dylib: $(AGENT_SRC) Agent/Loader.m Agent/LayerDrawing.m Agent/StatusBar.m
	mkdir -p $(BUILD) bin
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-arm64.o
	xcrun -sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-x86_64.o
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -fobjc-arc -c Agent/LayerDrawing.m -o $(BUILD)/LayerDrawing-arm64.o
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -fobjc-arc -c Agent/StatusBar.m -o $(BUILD)/StatusBar-arm64.o
	xcrun -sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator -O2 -fobjc-arc -c Agent/StatusBar.m -o $(BUILD)/StatusBar-x86_64.o
	xcrun -sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator -O2 -fobjc-arc -c Agent/LayerDrawing.m -o $(BUILD)/LayerDrawing-x86_64.o
	xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -sdk $(SIM_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-arm64.o $(BUILD)/LayerDrawing-arm64.o $(BUILD)/StatusBar-arm64.o -o $(BUILD)/agent-arm64.dylib
	xcrun -sdk iphonesimulator swiftc -target x86_64-apple-ios17.0-simulator -sdk $(SIM_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-x86_64.o $(BUILD)/LayerDrawing-x86_64.o $(BUILD)/StatusBar-x86_64.o -o $(BUILD)/agent-x86_64.dylib
	rm -f $@ && lipo -create $(BUILD)/agent-arm64.dylib $(BUILD)/agent-x86_64.dylib -output $@

bin/SwiftshotAgent-watchOS.dylib: $(AGENT_SRC) Agent/Loader.m Agent/SwiftCall.s Agent/WatchCapture.m Agent/LayerDrawing.m
	mkdir -p $(BUILD) bin
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-watch.o
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -O2 -fobjc-arc -c Agent/WatchCapture.m -o $(BUILD)/WatchCapture-watch.o
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -O2 -fobjc-arc -c Agent/LayerDrawing.m -o $(BUILD)/LayerDrawing-watch.o
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -c Agent/SwiftCall.s -o $(BUILD)/SwiftCall-watch.o
	xcrun -sdk watchsimulator swiftc -target arm64-apple-watchos10.0-simulator -sdk $(WATCH_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-watch.o $(BUILD)/SwiftCall-watch.o $(BUILD)/WatchCapture-watch.o $(BUILD)/LayerDrawing-watch.o -o $(BUILD)/agent-watch.dylib
	rm -f $@ && cp $(BUILD)/agent-watch.dylib $@

# No-boot rendering (the default): shim injected into simulator processes + the macOS host for them.
NOBOOT_SRC := Agent/NoBoot.c Agent/FakeDisplay.c Agent/SimFramebufferClient.tbd
NOBOOT_LINK := -framework CoreFoundation

bin/SwiftshotNoBoot.dylib: $(NOBOOT_SRC)
	mkdir -p bin
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -dynamiclib $(NOBOOT_SRC) $(NOBOOT_LINK) -o $@

bin/SwiftshotNoBoot-watchOS.dylib: $(NOBOOT_SRC)
	mkdir -p bin
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -O2 -dynamiclib $(NOBOOT_SRC) $(NOBOOT_LINK) -o $@

bin/swiftshot-simhost: Agent/SimHost.m
	mkdir -p bin
	xcrun clang -fobjc-arc -O2 -framework Foundation -framework Metal Agent/SimHost.m -o $@

install: all
	install -d $(PREFIX)/bin
	install bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib bin/SwiftshotNoBoot.dylib bin/SwiftshotNoBoot-watchOS.dylib bin/swiftshot-simhost $(PREFIX)/bin/

# A release archive: the CLI and everything it loads, for Apple silicon Macs.
VERSION ?= dev
dist:
	sed -i '' 's/^let swiftshotVersion = .*/let swiftshotVersion = "$(VERSION)"/' Sources/swiftshot/Version.swift
	$(MAKE) all
	sed -i '' 's/^let swiftshotVersion = .*/let swiftshotVersion = "dev"/' Sources/swiftshot/Version.swift
	rm -rf dist && mkdir -p dist/swiftshot/bin
	cp bin/swiftshot bin/swiftshot-simhost bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib bin/SwiftshotNoBoot.dylib bin/SwiftshotNoBoot-watchOS.dylib dist/swiftshot/bin/
	cp README.md LICENSE dist/swiftshot/ 2>/dev/null || cp README.md dist/swiftshot/
	tar -C dist -czf dist/swiftshot-macos-arm64.tar.gz swiftshot
	shasum -a 256 dist/swiftshot-macos-arm64.tar.gz | sed 's| dist/| |' > dist/swiftshot-macos-arm64.tar.gz.sha256

clean:
	rm -rf .build bin

.PHONY: all install clean dist
