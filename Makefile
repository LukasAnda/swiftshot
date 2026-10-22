# Builds the macOS CLI and the iOS-simulator agent dylib into ./bin
PREFIX ?= /usr/local
SIM_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
AGENT_SRC := Agent/Agent.swift Agent/WatchAgent.swift Agent/Common.swift Agent/Discovery.swift Shared/JobModel.swift
WATCH_SDK := $(shell xcrun --sdk watchsimulator --show-sdk-path)
BUILD := .build/agent

all: bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib bin/SwiftshotNoBoot.dylib bin/swiftshot-simhost

bin/swiftshot: Package.swift $(wildcard Sources/swiftshot/*.swift) Shared/JobModel.swift
	swift build -c release --product swiftshot
	mkdir -p bin && rm -f bin/swiftshot && cp .build/release/swiftshot bin/swiftshot

bin/SwiftshotAgent.dylib: $(AGENT_SRC) Agent/Loader.m
	mkdir -p $(BUILD) bin
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-arm64.o
	xcrun -sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-x86_64.o
	xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -sdk $(SIM_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-arm64.o -o $(BUILD)/agent-arm64.dylib
	xcrun -sdk iphonesimulator swiftc -target x86_64-apple-ios17.0-simulator -sdk $(SIM_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-x86_64.o -o $(BUILD)/agent-x86_64.dylib
	rm -f $@ && lipo -create $(BUILD)/agent-arm64.dylib $(BUILD)/agent-x86_64.dylib -output $@

bin/SwiftshotAgent-watchOS.dylib: $(AGENT_SRC) Agent/Loader.m Agent/SwiftCall.s
	mkdir -p $(BUILD) bin
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -O2 -c Agent/Loader.m -o $(BUILD)/Loader-watch.o
	xcrun -sdk watchsimulator clang -target arm64-apple-watchos10.0-simulator -c Agent/SwiftCall.s -o $(BUILD)/SwiftCall-watch.o
	xcrun -sdk watchsimulator swiftc -target arm64-apple-watchos10.0-simulator -sdk $(WATCH_SDK) -O -emit-library \
		-module-name SwiftshotAgent $(AGENT_SRC) $(BUILD)/Loader-watch.o $(BUILD)/SwiftCall-watch.o -o $(BUILD)/agent-watch.dylib
	rm -f $@ && cp $(BUILD)/agent-watch.dylib $@

# No-boot rendering (experimental): shim injected into simulator processes + the macOS host for them.
bin/SwiftshotNoBoot.dylib: Agent/NoBoot.c
	mkdir -p bin
	xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -O2 -dynamiclib Agent/NoBoot.c -o $@

bin/swiftshot-simhost: Agent/SimHost.m
	mkdir -p bin
	xcrun clang -fobjc-arc -O2 -framework Foundation -framework Metal Agent/SimHost.m -o $@

install: all
	install -d $(PREFIX)/bin
	install bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib bin/SwiftshotNoBoot.dylib bin/swiftshot-simhost $(PREFIX)/bin/

clean:
	rm -rf .build bin

.PHONY: all install clean
