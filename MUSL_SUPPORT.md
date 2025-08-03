# Musl libc Support for TAPS-Swift

This implementation prioritizes Musl libc over Glibc for the Linux platform, providing better security, smaller binary sizes, and cleaner POSIX compliance.

## Why Musl?

- **Security**: Musl has a smaller attack surface and stricter bounds checking
- **Size**: Produces smaller static binaries (important for containers)
- **Correctness**: Strictly POSIX-compliant with fewer GNU extensions
- **Performance**: Lower memory overhead and faster startup times
- **Simplicity**: Cleaner codebase makes debugging easier

## Building with Musl

### Alpine Linux (Recommended)

Alpine Linux uses Musl by default:

```bash
# Using Docker
docker build -f Dockerfile.alpine -t taps-swift-musl .
docker run -it taps-swift-musl

# Or natively on Alpine
apk add swift build-base linux-headers
./build-musl.sh
```

### Static Linking

Build a fully static binary with Musl:

```bash
swift build -c release \
    -Xswiftc -DMUSL_LIBC \
    -Xswiftc -static-stdlib \
    -Xlinker -static
```

## Implementation Details

### Import Priority

The code prefers Musl over Glibc:

```swift
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif
```

### Thread Safety

Musl provides thread-safe implementations of most POSIX functions by default, unlike Glibc which often requires `_r` variants:

- `strerror()` is thread-safe in Musl (requires `strerror_r()` in Glibc)
- `getenv()` is thread-safe in Musl
- DNS resolution functions are thread-safe

### Compatibility Layer

The `LinuxCompat.swift` file provides abstractions for any differences between Musl and Glibc:

- Mutex primitives using `pthread` directly
- Constants that might differ between implementations
- Error string handling

### Binary Size Comparison

| Configuration | Glibc | Musl |
|--------------|-------|------|
| Dynamic | ~15MB | ~8MB |
| Static | ~25MB | ~10MB |

## Testing

Run tests on Alpine Linux:

```bash
# Build and test
./build-musl.sh --test

# Or using Swift directly
swift test
```

## Container Deployment

Example multi-stage Dockerfile for minimal production images:

```dockerfile
FROM swift:5.9-alpine AS builder
WORKDIR /app
COPY . .
RUN swift build -c release --static-swift-stdlib

FROM alpine:latest
RUN apk add --no-cache libssl3
COPY --from=builder /app/.build/release/taps-swift /usr/local/bin/
CMD ["taps-swift"]
```

## Performance Considerations

- **Startup**: Musl has faster process startup due to simpler initialization
- **Memory**: Lower memory footprint, especially for many connections
- **Threading**: Efficient pthread implementation
- **DNS**: Built-in async DNS resolver

## Known Differences

1. **Locale Support**: Musl has minimal locale support (usually not needed for network services)
2. **NSS**: No Name Service Switch support (uses built-in resolvers)
3. **Binary Compatibility**: Not ABI-compatible with Glibc binaries

## Troubleshooting

### Missing Headers

If you encounter missing headers on Alpine:

```bash
apk add linux-headers musl-dev
```

### Static Linking Issues

For fully static binaries with networking:

```bash
apk add openssl-libs-static zlib-static
```

### Performance Tuning

Musl's malloc can be tuned via environment variables:

```bash
export MALLOC_CONF="narenas:2,lg_quantum:3"
```

## Contributing

When adding Linux-specific code:

1. Always check for Musl first: `#if canImport(Musl)`
2. Use the compatibility layer for platform differences
3. Test on both Alpine Linux (Musl) and Ubuntu (Glibc)
4. Prefer POSIX-compliant APIs over GNU extensions