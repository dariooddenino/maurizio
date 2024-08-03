#!/bin/bash
clear;
ls src/*.zig | entr sh -c "zig build test --summary new";
