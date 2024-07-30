#!/bin/sh
nm $1 | grep -i " T " | awk '{ print $1" "$3 }' > $1.sym
