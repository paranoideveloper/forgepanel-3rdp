# ForgePanel for a third-party host.
#
# The image is what actually gets deployed, so these targets exist to check the
# tree before pushing rather than to produce release artefacts.
#
# Named for Railway once, when that was the only target; the distribution now
# covers Fly, Render and Koyeb as well — see README.md for what each can carry.

GO ?= go

.PHONY: all build frontend test check image clean

all: check

# The frontend is embedded into the binary, so it has to be built first.
frontend:
	cd frontend && bun install && bun run build

build: frontend
	CGO_ENABLED=0 $(GO) build -trimpath -o bin/forgepanel ./cmd/forgepanel
	CGO_ENABLED=0 $(GO) build -trimpath -o bin/forgectl   ./cmd/forgectl

test:
	$(GO) test ./...
	cd frontend && bun run test

check: test
	$(GO) vet ./...
	gofmt -l internal cmd

# Exactly what Railway builds, so a failure here is a failure there.
image:
	docker build -f deploy/railway/Dockerfile -t forgepanel-railway:local .

clean:
	rm -rf bin
