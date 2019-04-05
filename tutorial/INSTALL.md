### Install LUX on Mac

> brew install hawk/homebrew-hawk/lux

## Install LUX from source

> git clone -b euc git@github.com:hawk/lux.git
> export ERL_COMPILER_OPTIONS='[debug_info]' # Only needed for debuggging
> cd lux
> autoconf
> ./configure
> make
> export "PATH=$PWD/bin:$PATH"

See ../INSTALL.md for more details about how to install LUX.

### Run tutorial demo programs

>     cd tutorial
>     make
