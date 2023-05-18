#!/usr/bin/env python

import subprocess

if subprocess.run(["grub-file", "--is-x86-multiboot", "zig-out/bin/kernel.bin"]).returncode != 0:
	print("kernel is not multiboot compliant")
else:
	print("multiboot confirmed")

