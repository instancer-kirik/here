# Multi-stage build for here - Universal Package Manager
FROM alpine:latest AS builder

# Install Zig
RUN apk add --no-cache curl xz && \
    curl -L https://ziglang.org/download/0.12.1/zig-linux-x86_64-0.12.1.tar.xz | tar -xJ -C /opt && \
    ln -s /opt/zig-linux-x86_64-0.12.1/zig /usr/local/bin/zig

# Set working directory
WORKDIR /src

# Copy source code
COPY . .

# Build static binary
RUN zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl

# Strip binary to reduce size
RUN strip zig-out/bin/here

# Final stage - minimal runtime image
FROM scratch

# Copy the static binary
COPY --from=builder /src/zig-out/bin/here /usr/local/bin/here

# Copy documentation
COPY --from=builder /src/README.md /README.md
COPY --from=builder /src/LICENSE /LICENSE

# Create a minimal filesystem structure
COPY --from=alpine:latest /etc/passwd /etc/passwd
COPY --from=alpine:latest /etc/group /etc/group

# Create non-root user
USER 1000:1000

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/here"]

# Default command
CMD ["help"]

# Labels
LABEL org.opencontainers.image.title="here"
LABEL org.opencontainers.image.description="Universal package manager that speaks your system's language"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.authors="here contributors"
LABEL org.opencontainers.image.url="https://github.com/your-repo/here"
LABEL org.opencontainers.image.source="https://github.com/your-repo/here"
LABEL org.opencontainers.image.licenses="MIT"
