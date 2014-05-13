## Dependencies

### Ubuntu 14.04

    sudo apt-get install git valac libgupnp-1.0-dev libgee-0.8-dev

    # tup build tool
    # see: http://gittup.org/tup/
    sudo apt-add-repository 'deb http://ppa.launchpad.net/anatol/tup/ubuntu precise main'
    sudo apt-get update
    sudo apt-get install tup

### Fedora 20

    sudo yum install fuse-devel gupnp-devel libgee-devel vala

    # setup Tup
    git clone git://github.com/gittup/tup.git
    cd tup
    ./bootstrap.sh

    sudo ln -s $PWD/tup /usr/local/bin/tup
    cd ..

## Get Source

    git clone https://github.com/cablelabs/librui-discoverer.git
    cd librui-discoverer

## Build

    tup init
    tup upd

While developing, it can be useful to leave `tup` running in the background, autocompiling every time anything changes:

    tup monitor -a
    # stop with 'tup stop'

## Linking

TODO
