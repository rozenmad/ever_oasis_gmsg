# ever_oasis_gmsm
Tool for unpack/repack gmsg files from EU ver. Ever Oasis 3DS <br />
Running on luajit 2.1.0

import - Repack inputgmsg_name.gmsg from inputmd_name.md to .gmsg <br />
export - Unpack inputgmsg_name.gmsg to .md

### How to use
```sh
luajit oasis.lua import inputgmsg_name inputmd_name outputgmsg_name
luajit oasis.lua export inputgmsg_name output_name
```

## Dependencies:
- luautf8
- binarylib
