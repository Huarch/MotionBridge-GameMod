# F8Studio startup and troubleshooting

## Expected startup order

1. Start F8Studio.
2. Import the Fallen Doll project and click Deploy.
3. Confirm all three entries in the service monitor:
   - `studio`: the UI itself;
   - `fd_pyengine`: the L0, safety, and TCode graph;
   - `fd_source`: the game skeleton reader.
4. Enable either USB or Wi-Fi, not both.
5. Start the game and enter HAnime.

Deploy should start `fd_pyengine` and `fd_source` automatically. They are not three
separate applications that players must launch by hand.

## Pixi startup issues

Source builds of F8Studio use Pixi for managed environments. A missing global
`pixi` command does not mean the installed Studio environment is broken. Avoid
mixing system Python, global Pixi, and the repository's `.pixi` environments:

- Studio uses `.pixi/envs/default/python.exe`;
- Fallen Doll Source uses `.pixi/envs/studio-runtime/python.exe`;
- for a source checkout, run this repository's
  `tools/Start-F8Studio.ps1 -F8StudioRoot "path"`; it locates the repository
  environments and an available Pixi without depending on global PATH.

Do not start a second Pixi/Studio environment while an existing Studio instance is
still running.

## Missing services

- Only `studio` appears: import the project and Deploy it; opening the JSON alone is
  not enough.
- `fd_pyengine` fails: the command may have resolved to the wrong environment, or an
  old child process may still exist. Stop All, close Studio, let its Python/Pixi
  children exit, then start Studio and Deploy again.
- `fd_source` fails: the F8Studio build must contain Fallen Doll Source. Until the
  upstream PR lands, use the supplied patch/branch.
- Services run but no data appears: `fd_source` connects only while the mod recognizes
  HAnime and receives fresh skeleton frames. No signal in menus, idle, or ordinary
  animation is expected.
- Hot deploy leaves stale state: use Stop All and Deploy again. A failed CLI state
  write is not by itself evidence of a game-mod failure.

## Isolate the failing segment

1. Game: confirm the UE4SS mod loaded; use F6 diagnostics or F10 hot reload if needed.
2. Source: confirm `fd_source` is Running/Active and `Game Stream` becomes true in
   HAnime.
3. Graph/device: verify the 3D or OSR Viewer, then TCode, and only then a physical
   device.

During a redeploy or action switch, the safety node holds the last value for 250 ms
and returns smoothly to center over 600 ms. A hard downward spike usually means an
older graph was imported.

## Device and shutdown

- Wi-Fi: `tcode.local:8000`; the PC and device must be mutually reachable.
- USB: select the actual serial port at 115200 baud.
- Never enable USB and Wi-Fi at the same time.
- After testing, disable physical output before stopping the graph and closing the game.
