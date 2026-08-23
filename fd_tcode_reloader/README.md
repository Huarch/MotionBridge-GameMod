# FD-TCode reload broker

This stable helper owns F10 and reloads `fd_tcode_probe`. It must not contain
runtime sampling, Unreal object references, delayed loops, or device output.

Keeping the key callback outside the target mod avoids closing a Lua state
while that same state is still returning from its F10 callback.
