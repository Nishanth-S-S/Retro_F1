#!/bin/sh
# Dev helper: run Godot with a time limit.  usage: ./run_godot.sh <seconds> <godot args...>
secs=$1; shift
exec perl -e 'alarm shift; exec @ARGV' "$secs" godot "$@"
