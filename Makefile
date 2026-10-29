.PHONY: app run install test clean

app:
	./scripts/bundle.sh

run: app
	-pkill -x Gunner
	open build/Gunner.app

install: app
	-pkill -x Gunner
	rm -rf /Applications/Gunner.app
	cp -R build/Gunner.app /Applications/
	open /Applications/Gunner.app

test:
	swift test

clean:
	rm -rf .build build
