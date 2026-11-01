#!/usr/bin/env sh

zig build
./tests/test_compiler zig-out/bin/cc2 --bitwise --increment --compound --goto --switch "$@"
