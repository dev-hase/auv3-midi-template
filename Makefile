# Convenience wrapper around XcodeGen + xcodebuild.

PROJECT = ArpMIDI.xcodeproj

.PHONY: project open build-macos validate clean

# Generate ArpMIDI.xcodeproj from project.yml.
project:
	xcodegen generate

open: project
	open $(PROJECT)

# Build the macOS host app (which embeds the AU extension).
build-macos: project
	xcodebuild -project $(PROJECT) -scheme Arp-macOS -configuration Debug build

# Run Apple's Audio Unit validation tool against the registered component.
validate:
	auval -v aumi arp1 Hase

clean:
	rm -rf $(PROJECT) build DerivedData
