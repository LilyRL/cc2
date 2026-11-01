#!/usr/bin/env sh

zig build run -- test.c --keep-intermediates
./test
echo "return code: $?"
