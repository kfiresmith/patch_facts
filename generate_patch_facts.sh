#!/bin/bash
#
# Facts:
#  - OS-Release (string)
#  - Security errata support (boolean)
#  - EOL (boolean)
#  - All Outstanding Packages Count (integer)
#  - Security Outstanding Packages Count (integer)
#  - ISO-8601 Date of Collection (string)
#
# 2021-04-18 Kodiak Firesmith <firesmith@protonmail.com>

EOL=("centos5"
     "centos6"
     "rhel5"
     "rhel6"
     "debian6"
     "debian7"
     "debian8"
     "ubuntu12"
     "ubuntu14"
     "ubuntu16"
     )

# We use dead-simple tests to infer OS type
if [ -f /etc/apt/sources.list ]; then os_type=debian
elif [ -f /etc/yum.conf ]; then os_type=redhat
fi

function discern_debvers() {
  repostring="$(egrep "^deb " /etc/apt/sources.list | grep "updates main")"


  errata_support=True

  case "$repostring" in
    *squeeze*)
      distro=debian
      distrovers=6
      EOL=True
      ;;
    *wheezy*)
      distro=debian
      distrovers=7
      EOL=True
      ;;
    *jessie*)
      distro=debian
      distrovers=8
      EOL=True
      ;;
    *stretch*)
      distro=debian
      distrovers=9
      EOL=False
      ;;
    *buster*)
      distro=debian
      distrovers=10
      EOL=False
      ;;
    *lucid*)
      distro=ubuntu
      distrovers=10
      EOL=True
      ;;
    *focal*)
      distro=ubuntu
      distrovers=20
      EOL=False
      ;;
    *groovy*)
      distro=ubuntu
      distrovers=20.10
      EOL=false
      ;;
    *)
      exit 3
  esac
}


case $os_type in
  debian)
    #stuff
    ;;
  redhat)
    #stuff
    ;;
  *)
    exit 2
    ;;
esac

if [ "$os_type" == "debian" ]; then
  discern_debvers
  echo "distro is $distro, version is $distrovers, EOL is $EOL"
  echo $distro
fi
